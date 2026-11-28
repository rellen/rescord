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
  import Rescord.ResidentsFixtures
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
    lists = lists!(organisation, root)
    biscuit = resident!(lists, admin, %{name: "Biscuit"})

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     admin: admin,
     ana: ana,
     biscuit: biscuit,
     lists: lists,
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
      assert html =~ "The administrators of Wattle Creek, whose role can change its settings"
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

  describe "the steps and the records of an answer" do
    test "a step while Ruby reads, and the step folded in the answer", context do
      {view, path} = ask(context, "Who is on medication today?")
      conversation_id = path |> String.split("/") |> List.last()
      reply = %{id: Ecto.UUID.generate(), conversation_id: conversation_id}

      step = %{
        "call_id" => "toolu_1",
        "tool" => "find_residents",
        "arguments" => %{},
        "state" => "running",
        "count" => nil,
        "refs" => []
      }

      Events.step(reply, step)
      assert has_element?(view, "#ruby-answer li[data-step=running]", "Looks for residents")
      assert has_element?(view, "[role=status]", "Ruby looks for residents.")

      Events.step(reply, %{step | "state" => "done", "count" => 3})
      assert has_element?(view, "#ruby-answer li[data-step=done]", "Looked for residents")
      assert has_element?(view, "#ruby-answer li[data-step=done] small", "3 residents")
      assert count(view, "#ruby-answer li[data-step]") == 1

      # Once Ruby writes, the steps fold.
      Events.text(reply, "Three residents.")
      refute has_element?(view, "#ruby-answer > ul[data-steps]")
      assert has_element?(view, "#ruby-answer details summary", "What Ruby read: 1 step")
    end

    test "a link and a card only for a record that a tool returned", context do
      biscuit = "resident:" <> context.biscuit.id
      stranger = "resident:" <> Ecto.UUID.generate()

      ScriptedModel.script([
        {:tool, "find_residents", %{}},
        {:text,
         "[Biscuit](#{biscuit}) is in care. [Clover](#{stranger}) is not. " <>
           "[Look](javascript:alert(1)) and [here](https://example.org/)."}
      ])

      {view, _path} = ask(context, "Who is on medication today?")
      work!()

      page = ~p"/o/#{context.organisation.short_name}/residents/#{context.biscuit.id}"
      ruby = "ol[data-chat] article[data-from=ruby]"

      assert has_element?(view, "#{ruby} [data-prose] a[href=\"#{page}\"]", "Biscuit")
      assert count(view, "#{ruby} [data-prose] a") == 1
      assert has_element?(view, "#{ruby} [data-prose]", "Clover is not.")
      assert has_element?(view, "#{ruby} [data-prose]", "Look and here.")
      refute main(view) =~ "javascript:"
      refute main(view) =~ "example.org"

      # The card of the record, below the words.
      assert has_element?(view, "#{ruby} footer h3", "From the records")
      assert has_element?(view, "#{ruby} footer a[href=\"#{page}\"] [data-portrait]", "B")
      assert count(view, "#{ruby} footer li") == 1

      # The step, folded.
      [_said, reply] = Ruby.messages!(conversation_of(context), context.as_ana)
      assert has_element?(view, "#steps-#{reply.id} summary", "What Ruby read: 1 step")
      assert has_element?(view, "#steps-#{reply.id} li[data-step=done]", "1 resident")

      # A page that opens again draws the same.
      {:ok, again, _html} = live(context.conn, context.path <> "/" <> reply.conversation_id)
      assert has_element?(again, "#{ruby} [data-prose] a[href=\"#{page}\"]", "Biscuit")
      assert has_element?(again, "#{ruby} footer a[href=\"#{page}\"]")
    end
  end

  describe "a conversation about a record" do
    test "from a resident: the card, the things to ask about it, and the conversation", context do
      ref = "resident:" <> context.biscuit.id
      page = ~p"/o/#{context.organisation.short_name}/residents/#{context.biscuit.id}"

      {:ok, view, _html} = live(context.conn, context.path <> "?" <> URI.encode_query(about: ref))

      assert has_element?(
               view,
               "main > a#ruby-about[data-about][href=\"#{page}\"]",
               "About Biscuit"
             )

      assert has_element?(view, "#ruby-about [data-portrait]", "B")

      assert has_element?(
               view,
               "ul[data-suggestions] button",
               "What happened to Biscuit this week?"
             )

      refute has_element?(view, "ul[data-suggestions] button", "What is running low?")

      view |> element("button", "What happened to Biscuit this week?") |> render_click()
      path = assert_patch(view)

      [conversation] = Ruby.conversations!(context.as_ana)
      assert conversation.about == ref
      assert path == context.path <> "/" <> conversation.id

      # The conversation keeps the card, and a page that opens it again shows it.
      assert has_element?(view, "#ruby-about[href=\"#{page}\"]", "About Biscuit")
      {:ok, again, _html} = live(context.conn, path)
      assert has_element?(again, "#ruby-about[href=\"#{page}\"]", "About Biscuit")

      # The header of the first message tells Ruby the record, by its
      # reference and not by its name.
      ScriptedModel.script([{:text, "Biscuit was weighed on Monday."}])
      work!()

      [%{messages: messages} | _rest] = ScriptedModel.requests()

      sent =
        for %{role: :user, content: parts} <- messages, %{text: text} <- parts, into: "", do: text

      assert sent =~ "about: " <> ref
      assert sent =~ "What happened to Biscuit this week?"
    end

    test "from an item of the inventory", context do
      hay =
        Rescord.Inventory.add_item!(
          %{name: "Meadow hay", unit_id: context.lists.unit.bag},
          context.admin
        )

      # An id in capitals is the same id.
      about = URI.encode_query(about: "item:" <> String.upcase(hay.id))
      {:ok, view, _html} = live(context.conn, context.path <> "?" <> about)

      assert has_element?(
               view,
               "#ruby-about[href=\"/o/#{context.organisation.short_name}/inventory/#{hay.id}\"]",
               "About Meadow hay"
             )

      refute has_element?(view, "#ruby-about [data-portrait]")
      assert has_element?(view, "ul[data-suggestions] button", "How much Meadow hay is left?")
    end

    test "a reference that names no record of the person is a plain start", context do
      for ref <- [
            "resident:" <> Ecto.UUID.generate(),
            "resident:not-an-id",
            "member:" <> context.ana.id,
            "Biscuit",
            "",
            String.duplicate("resident:", 1000)
          ] do
        {:ok, view, _html} =
          live(context.conn, context.path <> "?" <> URI.encode_query(about: ref))

        refute has_element?(view, "#ruby-about")
        assert has_element?(view, "ul[data-suggestions] button", "What is running low?")
      end

      # A list or a map in the place of the reference.
      for query <- ["about[]=x", "about[k]=v"] do
        {:ok, view, _html} = live(context.conn, context.path <> "?" <> query)

        refute has_element?(view, "#ruby-about")
        assert has_element?(view, "ul[data-suggestions] button", "What is running low?")
      end

      # A conversation about a record that is gone opens with no card.
      conversation =
        Ruby.start_conversation!(%{about: "resident:" <> Ecto.UUID.generate()}, context.as_ana)

      {:ok, view, _html} = live(context.conn, context.path <> "/" <> conversation.id)
      refute has_element?(view, "#ruby-about")
    end
  end

  describe "the links to Ruby" do
    test "in the bar, on the first page and on a resident, for who may ask",
         context do
      org = context.organisation.short_name
      ruby = ~p"/o/#{org}/ruby"

      {:ok, home, _html} = live(context.conn, ~p"/o/#{org}")
      assert has_element?(home, "header > nav > a[data-ruby][href=\"#{ruby}\"]", "Ruby")
      # One link in the navigation of the site: none in the menu besides.
      refute has_element?(home, "header nav ul a[data-ruby]")

      assert has_element?(
               home,
               "main nav ul[data-links] li:first-child a[href=\"#{ruby}\"]",
               "Ask Ruby"
             )

      {:ok, resident, _html} = live(context.conn, ~p"/o/#{org}/residents/#{context.biscuit.id}")
      about = ruby <> "?" <> URI.encode_query(about: "resident:" <> context.biscuit.id)
      assert has_element?(resident, "main a#ask-ruby[href=\"#{about}\"]", "Ask Ruby")

      {:ok, tasks, _html} = live(context.conn, ~p"/o/#{org}/tasks")
      assert has_element?(tasks, "main a#ask-ruby[href=\"#{ruby}\"]", "Ask Ruby")

      # The page of Ruby is the current one in the bar.
      {:ok, page, _html} = live(context.conn, ruby)
      assert has_element?(page, "header > nav > a[data-ruby][aria-current]")
    end

    test "a person who cannot ask Ruby finds no link", context do
      org = context.organisation.short_name
      {_, other} = member!(context.organisation, :member, context.administrator)
      conn = sign_in(build_conn(), other)

      for path <- [
            ~p"/o/#{org}",
            ~p"/o/#{org}/residents/#{context.biscuit.id}",
            ~p"/o/#{org}/tasks"
          ] do
        {:ok, view, _html} = live(conn, path)
        refute has_element?(view, "a[href^=\"/o/#{org}/ruby\"]")
        refute has_element?(view, "a[data-ruby]")
        refute has_element?(view, "#ask-ruby")
      end

      # Nor does anybody while Ruby is off.
      {:ok, _settings} = Ruby.save_settings(%{enabled: false}, context.admin)
      {:ok, view, _html} = live(context.conn, ~p"/o/#{org}/residents/#{context.biscuit.id}")
      refute has_element?(view, "a[data-ruby]")
      refute has_element?(view, "#ask-ruby")
    end
  end

  describe "what goes wrong" do
    # Asks, and runs the job with the script: the answer fails for a reason.
    defp answered(context, script) do
      ScriptedModel.script(script)
      {view, path} = ask(context, "Who is on medication today?")
      capture_log(fn -> work!() end)
      {view, path}
    end

    defp alert(view),
      do: view |> element("ol[data-chat] article[data-from=ruby] [role=alert]") |> render()

    test "each failure of a reply says what happened, and its way on", context do
      overloaded = %{status: 529}

      for {script, words, way} <- [
            {[{:error, :timeout}], "the service that Ruby thinks with did not respond",
             "Try again"},
            {[{:error, overloaded}], "Ruby is busy. Nothing was recorded.", "Try again"},
            {[{:error, %{status: 400}}], "refused the request", "New conversation"},
            {[{:error, %{status: 401}}], "Ruby is not set up on this server", nil},
            {[{:error, %{status: 400, reason: "usage limits"}}],
             "the limit of this server for the month", nil},
            {List.duplicate({:tool, "find_residents", %{}}, 8), "took too many steps", nil}
          ] do
        {view, _path} = answered(context, script)

        assert alert(view) =~ words
        assert alert(view) =~ "Nothing was recorded" or words =~ "too many steps"

        ways = view |> element("ol[data-chat]") |> render()

        if way,
          do: assert(has_element?(view, "ol[data-chat] [data-way-on]", way)),
          else: refute(ways =~ "data-way-on")

        # The field stays, but after "New conversation".
        assert has_element?(view, "#ruby-message")
      end
    end

    test "Try again sends the message of the member again", context do
      {view, _path} = answered(context, [{:error, :timeout}])

      view |> element("[data-way-on] button", "Try again") |> render_click()

      assert count(view, "ol[data-chat] article[data-from=member]") == 2
      assert has_element?(view, "#ruby-answer", "is working")
      # The way on of the reply before is gone while Ruby answers.
      refute has_element?(view, "[data-way-on]")

      ScriptedModel.script([{:text, "Two residents."}])
      work!()
      assert has_element?(view, "ol[data-chat] article[data-from=ruby]", "Two residents.")
    end

    test "Try again only for the last reply, and only where a second try can go better",
         context do
      {view, _path} = answered(context, [{:error, :timeout}])
      [asked, _reply] = Ruby.messages!(conversation_of(context), context.as_ana)

      # A reply that was cut cannot be tried again by a crafted event.
      view |> form("#ruby-say", message: %{text: "And tomorrow?"}) |> render_submit()
      ScriptedModel.script([{:cut, "Tomorrow"}])
      work!()
      render_hook(view, "again", %{"id" => asked.id})

      assert count(view, "ol[data-chat] article[data-from=member]") == 2
      refute has_element?(view, "#ruby-answer")
    end

    test "a message that comes too fast stays in the field, and Try again sends it", context do
      # Six messages in a minute are the most that a member sends.
      ScriptedModel.script(List.duplicate({:text, "Two."}, 6))
      {view, _path} = ask(context, "Who is on medication today?")
      work!()

      for n <- 2..6 do
        view |> form("#ruby-say", message: %{text: "And #{n}?"}) |> render_submit()
        work!()
      end

      view |> form("#ruby-say", message: %{text: "And seven?"}) |> render_submit()

      assert has_element?(
               view,
               "main [data-problem] [role=alert]",
               "Wait a moment before you ask again."
             )

      assert has_element?(view, "#ruby-message", "And seven?")
      assert has_element?(view, "[data-problem] button[form=ruby-say]", "Try again")
      # One Try again: the reply before has none while the refusal shows.
      assert count(view, "[data-way-on]") == 1
      assert count(view, "ol[data-chat] article[data-from=member]") == 6
    end

    test "a refusal hides its words and closes the conversation", context do
      {view, _path} = answered(context, [{:refusal, "I will not say this."}])

      assert alert(view) =~ "Ruby cannot help with that. Nothing was recorded."
      refute main(view) =~ "I will not say this."
      refute has_element?(view, "#ruby-say")
      assert has_element?(view, "#ruby-closed", "This conversation is closed.")
      assert has_element?(view, "#ruby-closed a", "New conversation")
    end

    test "an answer that was cut keeps its words, and asks for the rest", context do
      {view, _path} = answered(context, [{:cut, "Biscuit and Clover are"}])

      ruby = "ol[data-chat] article[data-from=ruby]"
      assert has_element?(view, ruby, "Biscuit and Clover are")
      assert has_element?(view, ruby, "The answer was cut short. Ask for the rest.")
      refute has_element?(view, "#{ruby} [role=alert]")

      view |> element("[data-way-on] button", "Ask for the rest") |> render_click()

      assert has_element?(
               view,
               "ol[data-chat] article[data-from=member]",
               "Please go on with the rest of the answer."
             )
    end

    test "a message past the allowance is refused, with the way to the settings for who sets them",
         context do
      [offer] = Ruby.offers(context.admin)

      {:ok, _settings} =
        Ruby.save_settings(
          %{enabled: true, provider_id: offer.id, agreed_to: offer.place_key, allowance: 0},
          context.admin
        )

      {:ok, view, _html} = live(context.conn, context.path)
      view |> element("button", "Who is on medication today?") |> render_click()

      assert has_element?(
               view,
               "main [role=alert]",
               "Ruby has no allowance for #{context.organisation.name}"
             )

      refute has_element?(view, "[data-way-on]")
      assert Ruby.conversations!(context.as_ana) == []

      # An administrator gets the link to the settings.
      conn = sign_in(build_conn(), context.administrator)
      {:ok, view, _html} = live(conn, context.path)
      view |> element("button", "Who is on medication today?") |> render_click()

      assert has_element?(
               view,
               "[data-way-on] a[href=\"/o/#{context.organisation.short_name}/settings/ruby\"]"
             )
    end

    test "a page that opens in the middle of an answer shows the words so far", context do
      conversation = Ruby.start_conversation!(%{}, context.as_ana)
      message = Ruby.say!(conversation.id, "Who is on medication today?", context.as_ana)
      {:ok, reply} = Rescord.Ruby.Replies.open(message, context.organisation)

      :ok =
        Rescord.Ruby.Replies.save(
          reply,
          %{text: "Biscuit gets **a sample**"},
          context.organisation
        )

      {:ok, view, _html} = live(context.conn, context.path <> "/" <> conversation.id)
      assert has_element?(view, "#ruby-answer [data-prose] strong", "a sample")
      assert has_element?(view, "#ruby-answer", "is writing")
      assert has_element?(view, "#ruby-stop")
    end
  end

  defp conversation_of(context) do
    [conversation] = Ruby.conversations!(context.as_ana)
    conversation.id
  end
end
