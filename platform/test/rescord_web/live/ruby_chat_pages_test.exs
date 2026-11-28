defmodule RescordWeb.RubyChatPagesTest do
  @moduledoc """
  Holds the page of Ruby (ADR 0069): who opens it, the start with the
  things to ask, a question and its answer as the page hears it, Stop, a
  reply that failed, and a conversation of another member.

  The job of a reply runs in the test process, with the scripted model. No
  test calls a provider.

  Each test creates an organisation, so the tests do not run beside others.
  """

  use RescordWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures
  import Rescord.RubyFixtures

  alias Rescord.{Accounts, Ruby}
  alias Rescord.Ruby.{Events, ScriptedModel}

  setup context do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    admin = [actor: administrator, tenant: organisation]

    # A carer may ask Ruby, and has the powers of a member besides.
    {:ok, carer} = Accounts.define_role(%{name: "Carer", powers: [:ruby]}, admin)
    {ana_member, ana} = member!(organisation, :member, administrator)
    {:ok, _member} = Accounts.set_member_role(ana_member, carer.id, admin)

    ruby_on!(root, admin)

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     admin: admin,
     ana: ana,
     as_ana: [actor: ana, tenant: organisation],
     path: ~p"/o/#{organisation.short_name}/ruby",
     conn: sign_in(context.conn, ana)}
  end

  # Runs the jobs of the queue in this process. A fault fails the test.
  defp work!, do: Oban.drain_queue(queue: :ruby, with_safety: false)

  # Asks a thing to ask on the start, and follows the page to the
  # conversation.
  defp ask(context, words) do
    {:ok, view, _html} = live(context.conn, context.path)
    view |> element("button", words) |> render_click()
    path = assert_patch(view)
    {view, path}
  end

  defp main(view), do: view |> element("main") |> render()

  defp count(view, selector),
    do: view |> render() |> LazyHTML.from_document() |> LazyHTML.query(selector) |> Enum.count()

  describe "who opens the page" do
    test "a member who may ask Ruby, with no class in the markup", context do
      {:ok, view, html} = live(context.conn, context.path)

      assert html =~ "The assistant of Wattle Creek"
      assert html =~ "The administrators of Wattle Creek can read what you ask Ruby."
      assert has_element?(view, "main[data-ruby] form#ruby-say[data-composer]")
      assert has_element?(view, "#ruby-send", "Send")
      refute main(view) =~ ~r/\sclass=/
    end

    test "nobody else: the address is a page that is not there", context do
      # A member whose role does not have the power.
      {_, other} = member!(context.organisation, :member, context.administrator)

      assert_raise RescordWeb.NotFound, fn ->
        live(sign_in(build_conn(), other), context.path)
      end

      # A root user who is no member.
      assert_raise RescordWeb.NotFound, fn ->
        live(sign_in(build_conn(), context.root), context.path)
      end

      # Ruby is off for the organisation.
      {:ok, _settings} = Ruby.save_settings(%{enabled: false}, context.admin)

      assert_raise RescordWeb.NotFound, fn -> live(context.conn, context.path) end
    end

    test "a conversation of another member goes back to the start", context do
      theirs = Ruby.start_conversation!(%{}, context.admin)
      path = context.path <> "/" <> theirs.id

      assert {:error, {:live_redirect, %{to: to, flash: flash}}} = live(context.conn, path)
      assert to == context.path
      assert flash["error"] == "There is no such conversation."

      assert {:error, {:live_redirect, %{to: ^to}}} =
               live(context.conn, context.path <> "/not-an-id")
    end
  end

  describe "the start" do
    test "offers the things to ask that the role can read", context do
      {:ok, view, _html} = live(context.conn, context.path)

      # The first four that the tools of the carer answer.
      assert count(view, "[data-suggestions] li") == 4

      for words <- ["What is still to do today?", "What is running low?"],
          do: assert(has_element?(view, "ul[data-suggestions] button", words))

      # A thing to ask needs its tool, for this person.
      assert Ruby.reads?(context.ana, context.organisation, "care_overview")
      refute Ruby.reads?(context.ana, context.organisation, "no_such_tool")
      refute Ruby.reads?(user!(), context.organisation, "care_overview")
      refute Ruby.reads?(nil, context.organisation, "care_overview")
    end

    test "lists the last conversations of the person, at their newest message", context do
      conversation = Ruby.start_conversation!(%{}, context.as_ana)
      Ruby.start_conversation!(%{}, context.admin)

      {:ok, view, _html} = live(context.conn, context.path)

      assert has_element?(
               view,
               ~s(a[href="#{context.path}/#{conversation.id}#newest"]),
               "A new conversation"
             )

      assert count(view, "[data-links] li") == 1
    end

    test "sends no blank message, and makes no conversation for one", context do
      {:ok, view, _html} = live(context.conn, context.path)
      view |> form("#ruby-say", message: %{text: "   "}) |> render_submit()

      assert Ruby.conversations!(context.as_ana) == []
      refute has_element?(view, "section[data-log]")
    end
  end

  describe "a conversation" do
    test "a question, the words as they arrive, and the answer", context do
      {view, path} = ask(context, "Who is on medication today?")
      [conversation] = Ruby.conversations!(context.as_ana)
      assert path == context.path <> "/" <> conversation.id

      # The question is in the list, and Ruby is working.
      assert has_element?(view, "ol[data-chat] article[data-from=member]", "Who is on medication")
      assert has_element?(view, "#ruby-answer", "is working")
      assert has_element?(view, "[role=status]", "Ruby is working.")
      assert has_element?(view, "#ruby-stop", "Stop")
      refute has_element?(view, "#ruby-send")

      # The words so far, as the job tells them: Markdown that is still
      # open is closed.
      Events.text(%{id: Ecto.UUID.generate(), conversation_id: conversation.id}, "**Biscuit")
      assert has_element?(view, "#ruby-answer [data-prose] strong", "Biscuit")
      assert has_element?(view, "#ruby-answer", "is writing")
      assert has_element?(view, "[role=status]", "Ruby is writing the answer.")

      ScriptedModel.script([{:text, "Biscuit gets a **sample antibiotic** today."}])
      work!()

      refute has_element?(view, "#ruby-answer")

      assert has_element?(
               view,
               "ol[data-chat] article[data-from=ruby] strong",
               "sample antibiotic"
             )

      assert has_element?(view, "[role=status]", "Ruby answered.")
      assert has_element?(view, "#ruby-send", "Send")

      # The conversation has the title that Ruby gave it, and the next
      # question goes on in it.
      assert has_element?(view, "h1", Ruby.conversation!(conversation.id, context.as_ana).title)

      view |> form("#ruby-say", message: %{text: "And tomorrow?"}) |> render_submit()
      assert has_element?(view, "ol[data-chat] article[data-from=member]", "And tomorrow?")
      assert has_element?(view, "#ruby-answer", "is working")
    end

    test "a page that opens again shows the conversation as it is", context do
      {_view, path} = ask(context, "Who is on medication today?")
      ScriptedModel.script([{:text, "Nobody today."}])
      work!()

      {:ok, view, _html} = live(context.conn, path)
      assert has_element?(view, "article[data-from=member]", "Who is on medication today?")
      assert has_element?(view, "article[data-from=ruby]", "Nobody today.")
      refute has_element?(view, "#ruby-answer")
    end

    test "Stop ends the answer, and keeps the conversation", context do
      {view, _path} = ask(context, "Who is on medication today?")
      view |> element("#ruby-stop") |> render_click()

      ScriptedModel.script([{:text, "Never read."}])
      work!()

      assert has_element?(view, "article[data-from=ruby]", "You stopped this answer.")
      assert has_element?(view, "[role=status]", "You stopped the answer.")
      assert has_element?(view, "#ruby-send")
    end

    test "a reply that failed says so, and that nothing was recorded", context do
      {view, _path} = ask(context, "Who is on medication today?")
      # Ruby is off by the time the job runs.
      {:ok, _settings} = Ruby.save_settings(%{enabled: false}, context.admin)
      capture_log(fn -> work!() end)

      assert has_element?(view, "article[data-from=ruby] [role=alert]", "Nothing was recorded.")
      assert has_element?(view, "[role=status]", "Ruby could not answer.")
    end
  end
end
