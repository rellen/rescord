defmodule RescordWeb.RubyConversationsPagesTest do
  @moduledoc """
  Holds "Your conversations" with Ruby (ADR 0069): who opens it, what each
  card says, the search, and the removal of all the conversations of a
  member; and on the page of one conversation, its new name and its
  removal. The tests find what a person finds (ADR 0107).

  No test calls a provider: no reply runs here.

  Each test creates an organisation, so the tests do not run beside others.
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.RubyFixtures

  alias Rescord.{Accounts, Ruby}

  setup context do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    admin = [actor: administrator, tenant: organisation]

    # A carer may ask Ruby.
    {:ok, carer} = Accounts.define_role(%{name: "Carer", powers: [:ruby]}, admin)
    {ana_member, ana} = member!(organisation, :member, administrator)
    {:ok, _member} = Accounts.set_member_role(ana_member, carer.id, admin)

    ruby_on!(root, admin)
    biscuit = resident!(lists!(organisation, root), admin, %{name: "Biscuit"})
    ruby = ~p"/o/#{organisation.short_name}/ruby"

    {:ok,
     organisation: organisation,
     administrator: administrator,
     admin: admin,
     biscuit: biscuit,
     as_ana: [actor: ana, tenant: organisation],
     ruby: ruby,
     list: ruby <> "/conversations",
     conn: sign_in(context.conn, ana)}
  end

  # A conversation with one message of the member.
  defp conversation!(options, words, values \\ %{}) do
    conversation = Ruby.start_conversation!(values, options)
    Ruby.say!(conversation.id, words, options)
    conversation
  end

  defp cards, do: main() |> region("Your conversations")

  describe "your conversations" do
    test "the conversations of the person, newest first, with what each is about", context do
      conversation!(context.as_ana, "When was Biscuit last weighed?", %{
        about: "resident:" <> context.biscuit.id
      })

      conversation!(context.as_ana, "What is running low?")

      # A conversation of another member is not in the list, also not for
      # an administrator, who reads each one elsewhere.
      conversation!(context.admin, "Who is in the barn?")

      session =
        context.conn
        |> visit(context.list)
        |> assert_has(main() |> heading(level: 1), text: "Your conversations")
        |> assert_has(main(),
          text: "The administrators of Wattle Creek can read what you ask Ruby."
        )
        |> assert_has(main(), text: "removes a conversation 90 days after its last message")
        |> assert_has(
          cards()
          |> link(~r/^When was Biscuit last weighed\? .* · about Biscuit · 1 message$/)
        )
        |> assert_has(cards() |> link(~r/^What is running low\? .* · 1 message$/))
        |> refute_has(cards() |> link(~r/Who is in the barn/))

      assert names(session, cards() |> link(~r/ · 1 message$/))
             |> Enum.map(&hd(String.split(&1, "?"))) ==
               ["What is running low", "When was Biscuit last weighed"]

      # The search finds a conversation by its name.
      session
      |> fill_in("Find a conversation", with: "Biscuit")
      |> assert_has(cards() |> link(~r/^When was Biscuit last weighed\?/))
      |> refute_has(cards() |> link(~r/^What is running low\?/))
    end

    test "the start leads to it, and a card leads to its conversation", context do
      conversation = conversation!(context.as_ana, "What is running low?")

      context.conn
      |> visit(context.ruby)
      |> click(main() |> link("All your conversations"))
      |> assert_path(context.list)
      |> click(cards() |> link(~r/^What is running low\?/))
      |> assert_path(context.ruby <> "/" <> conversation.id)
    end

    test "nobody else: the address is a page that is not there", context do
      {_, other} = member!(context.organisation, :member, context.administrator)

      assert_raise RescordWeb.NotFound, fn ->
        build_conn() |> sign_in(other) |> visit(context.list)
      end
    end

    test "remove all: each conversation of the person goes, and none of another", context do
      conversation!(context.as_ana, "What is running low?")
      theirs = conversation!(context.admin, "Who is in the barn?")

      context.conn
      |> visit(context.list)
      |> click(main() |> button("Remove all of your conversations"))
      |> assert_path(context.ruby)
      |> assert_has(status(), text: "Your conversations with Ruby are removed.")

      assert Ruby.conversations!(context.as_ana) == []
      assert [%{id: id}] = Ruby.conversations!(context.admin)
      assert id == theirs.id
    end

    test "remove all, by an administrator: the conversations of a member stay", context do
      mine = conversation!(context.as_ana, "What is running low?")
      conversation!(context.admin, "Who is in the barn?")

      build_conn()
      |> sign_in(context.administrator)
      |> visit(context.list)
      |> refute_has(cards() |> link(~r/^What is running low\?/))
      |> click(main() |> button("Remove all of your conversations"))
      |> assert_path(context.ruby)

      assert Ruby.conversations!(context.admin) == []
      assert [%{id: id}] = Ruby.conversations!(context.as_ana)
      assert id == mine.id
    end
  end

  describe "one conversation" do
    test "a new name, and no blank one", context do
      conversation = conversation!(context.as_ana, "What is running low?")

      context.conn
      |> visit(context.ruby <> "/" <> conversation.id)
      |> fill_in("Name of the conversation", with: "  ")
      |> click(main() |> button("Save the name"))
      |> assert_has(main(), text: "give the conversation a name")
      |> fill_in("Name of the conversation", with: "Hay for December")
      |> click(main() |> button("Save the name"))
      |> assert_has(main() |> heading(level: 1), text: "Hay for December")

      assert Ruby.conversation!(conversation.id, context.as_ana).title == "Hay for December"
    end

    test "a new name for a conversation that another tab removed leads to the start", context do
      conversation = conversation!(context.as_ana, "What is running low?")
      session = visit(context.conn, context.ruby <> "/" <> conversation.id)
      :ok = Ruby.remove_conversation(conversation, context.as_ana)

      session
      |> fill_in("Name of the conversation", with: "Hay for December")
      |> click(main() |> button("Save the name"))
      |> assert_path(context.ruby)
    end

    test "its removal, with its messages", context do
      conversation = conversation!(context.as_ana, "What is running low?")

      context.conn
      |> visit(context.ruby <> "/" <> conversation.id)
      |> click(main() |> button("Remove this conversation"))
      |> assert_path(context.list)
      |> assert_has(status(), text: "The conversation is removed.")
      |> refute_has(cards() |> link(~r/^What is running low\?/))

      assert Ruby.conversation!(conversation.id, context.as_ana) == nil
      assert {:ok, []} = Ruby.messages(conversation.id, context.as_ana)
    end
  end
end
