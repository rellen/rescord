defmodule Rescord.Ruby.ConversationsTest do
  @moduledoc """
  Holds who reads and who changes a conversation with Ruby (ADR 0069): its
  member alone, with the power `ruby`; a person with the power `settings`
  reads each one and changes none; and nobody else, a root user who is no
  member too. It holds also that a removal deletes for real.

  The test creates an organisation, so it does not run beside others.
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.RubyFixtures

  alias Rescord.{Accounts, Ruby}
  alias Rescord.Ruby.{Conversation, Message, Title}

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    admin = [actor: administrator, tenant: organisation]

    {:ok, asker} = Accounts.define_role(%{name: "Asker", powers: [:ruby]}, admin)
    {:ok, keeper} = Accounts.define_role(%{name: "Keeper", powers: [:settings]}, admin)

    with_role = fn role ->
      {member, user} = member!(organisation, :member, administrator)
      {:ok, _member} = Accounts.set_member_role(member, role.id, admin)
      {member, user}
    end

    {ana_member, ana} = with_role.(asker)
    {_, ben} = with_role.(asker)
    {_, kim} = with_role.(keeper)
    # The role `member` of a new organisation has no power `ruby`.
    {_, reader} = member!(organisation, :member, administrator)

    # A member says a thing only where Ruby is on. The job of each message
    # stays in its queue: `Rescord.Ruby.RepliesTest` runs the jobs.
    ruby_on!(root, admin)

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     admin: admin,
     asker: asker,
     ana_member: ana_member,
     ana: ana,
     ben: ben,
     kim: kim,
     reader: reader}
  end

  defp as(context, user), do: [actor: user, tenant: context.organisation]

  # A conversation of Ana with one message.
  defp talk!(context, text \\ "Which residents need their medication today?") do
    conversation = Ruby.start_conversation!(%{}, as(context, context.ana))
    message = Ruby.say!(conversation.id, text, as(context, context.ana))
    {conversation, message}
  end

  # A reply of Ruby. No action of a member makes one: the job does.
  defp reply!(context, conversation, message) do
    Ash.Seed.seed!(
      Message,
      %{
        conversation_id: conversation.id,
        owner_id: conversation.owner_id,
        response_to_id: message.id,
        source: :ruby,
        state: :complete,
        text: "Three of them."
      },
      tenant: context.organisation
    )
  end

  defp all(resource, context),
    do: Ash.read!(resource, tenant: context.organisation, authorize?: false)

  defp forbidden?({:error, %Ash.Error.Forbidden{}}), do: true
  defp forbidden?(_other), do: false

  describe "a member with the power ruby" do
    test "starts a conversation of their own, and says something in it", context do
      options = as(context, context.ana)

      assert {:ok, conversation} = Ruby.start_conversation(%{}, options)
      assert conversation.owner_id == context.ana.id
      assert conversation.title == nil

      assert {:ok, message} = Ruby.say(conversation.id, "  Who is due back\ntoday?  ", options)
      assert message.owner_id == context.ana.id
      assert message.source == :user
      assert message.text == "Who is due back\ntoday?"

      assert {:ok, [read]} = Ruby.conversations(options)
      assert read.id == conversation.id
      assert read.title == "Who is due back today?"
      assert DateTime.compare(read.last_message_at, conversation.last_message_at) != :lt

      assert {:ok, one} = Ruby.conversation(conversation.id, [load: [:messages]] ++ options)
      assert [%{id: id}] = one.messages
      assert id == message.id
    end

    test "cannot name the owner of a conversation or of a message", context do
      options = as(context, context.ana)

      assert {:error, _refused} =
               Ruby.start_conversation(%{owner_id: context.ben.id}, options)

      conversation = Ruby.start_conversation!(%{}, options)

      assert {:error, _refused} =
               Message
               |> Ash.Changeset.for_create(
                 :say,
                 %{conversation_id: conversation.id, text: "Hello", owner_id: context.ben.id},
                 options
               )
               |> Ash.create()
    end

    test "keeps the first title when more messages come", context do
      {conversation, message} = talk!(context, "The first words")
      # A conversation takes one message at a time.
      reply!(context, conversation, message)
      Ruby.say!(conversation.id, "Other words", as(context, context.ana))

      assert {:ok, %{title: "The first words"}} =
               Ruby.conversation(conversation.id, as(context, context.ana))
    end

    test "gives a conversation another name", context do
      {conversation, _message} = talk!(context)
      options = as(context, context.ana)

      assert {:ok, %{title: "Medication"}} =
               Ruby.rename_conversation(conversation, "Medication", options)

      assert {:error, _refused} = Ruby.rename_conversation(conversation, "", options)
    end

    test "says nothing with no words, and nothing longer than the limit", context do
      conversation = Ruby.start_conversation!(%{}, as(context, context.ana))
      options = as(context, context.ana)

      assert {:error, _refused} = Ruby.say(conversation.id, "   \n ", options)
      assert {:error, _refused} = Ruby.say(conversation.id, String.duplicate("a", 4_001), options)
      assert {:ok, _message} = Ruby.say(conversation.id, String.duplicate("a", 4_000), options)
    end

    test "opens a conversation from a record, and from nothing else", context do
      options = as(context, context.ana)
      about = "resident:#{Ash.UUID.generate()}"

      assert {:ok, %{about: ^about}} = Ruby.start_conversation(%{about: about}, options)

      assert {:error, _refused} =
               Ruby.start_conversation(%{about: "https://example.org"}, options)
    end

    test "rates a reply and stops a reply of their own, and not the other way", context do
      {conversation, message} = talk!(context)
      reply = reply!(context, conversation, message)
      options = as(context, context.ana)

      assert {:ok, %{rating: :down, rating_note: "Not so"}} =
               Ruby.rate_reply(reply, :down, %{rating_note: "Not so"}, options)

      assert {:error, _refused} = Ruby.rate_reply(message, :up, options)

      assert {:ok, %{stop_requested: true}} = Ruby.stop_reply(message, options)
      assert {:error, _refused} = Ruby.stop_reply(reply, options)
    end
  end

  describe "another member" do
    test "with the power ruby reads nothing of the conversation", context do
      {conversation, _message} = talk!(context)
      options = as(context, context.ben)

      assert {:ok, []} = Ruby.conversations(options)
      assert {:ok, nil} = Ruby.conversation(conversation.id, options)
      assert Ash.read!(Conversation, options) == []
      assert Ash.read!(Message, options) == []
      assert {:ok, []} = Ruby.conversations_of(context.ana.id, options)
      assert {:ok, nil} = Ruby.conversation_of(conversation.id, context.ana.id, options)
    end

    test "with the power ruby changes nothing of it", context do
      {conversation, message} = talk!(context)
      reply = reply!(context, conversation, message)
      options = as(context, context.ben)

      assert {:error, _refused} = Ruby.say(conversation.id, "Me too", options)
      assert forbidden?(Ruby.rename_conversation(conversation, "Mine now", options))
      assert forbidden?(Ruby.remove_conversation(conversation, options))
      assert forbidden?(Ruby.rate_reply(reply, :up, options))
      assert forbidden?(Ruby.stop_reply(message, options))

      assert [%{title: title}] = all(Conversation, context)
      assert title != "Mine now"
      assert [_message, _reply] = all(Message, context)
    end

    test "gets the same answer for a conversation of another person as for none", context do
      {conversation, _message} = talk!(context)
      options = as(context, context.ben)

      assert {:error, theirs} = Ruby.say(conversation.id, "Hello", options)
      assert {:error, none} = Ruby.say(Ash.UUIDv7.generate(), "Hello", options)
      assert Ruby.problems(theirs) == Ruby.problems(none)
      assert [{:conversation_id, "is no conversation of this person"}] = Ruby.problems(theirs)
    end

    test "with no power ruby starts nothing and reads nothing", context do
      {_conversation, _message} = talk!(context)
      options = as(context, context.reader)

      assert forbidden?(Ruby.start_conversation(%{}, options))
      assert {:ok, []} = Ruby.conversations(options)
      assert Ash.read!(Conversation, options) == []
      assert Ash.read!(Message, options) == []
    end

    test "who lost the power ruby reads their own no more", context do
      {conversation, _message} = talk!(context)

      {:ok, _role} = Accounts.revise_role(context.asker, %{powers: []}, context.admin)
      options = as(context, context.ana)

      assert {:ok, []} = Ruby.conversations(options)
      assert {:error, _refused} = Ruby.say(conversation.id, "Still here?", options)
      assert forbidden?(Ruby.start_conversation(%{}, options))
    end
  end

  describe "a root user who is no member of the organisation" do
    test "reads no conversation and no message, and starts none", context do
      {conversation, _message} = talk!(context)
      options = as(context, context.root)

      assert Ash.read!(Conversation, options) == []
      assert Ash.read!(Message, options) == []
      assert {:ok, []} = Ruby.conversations(options)
      assert {:ok, []} = Ruby.conversations_of(context.ana.id, options)
      assert {:ok, nil} = Ruby.conversation_of(conversation.id, context.ana.id, options)
      assert forbidden?(Ruby.start_conversation(%{}, options))
      assert forbidden?(Ruby.remove_conversation(conversation, options))
    end
  end

  describe "a person with the power settings" do
    test "reads each conversation of a member, with its messages", context do
      {conversation, message} = talk!(context)
      options = as(context, context.kim)

      assert {:ok, [read]} = Ruby.conversations_of(context.ana.id, options)
      assert read.id == conversation.id
      assert {:ok, []} = Ruby.conversations_of(context.ben.id, options)

      assert {:ok, one} =
               Ruby.conversation_of(
                 conversation.id,
                 context.ana.id,
                 [load: [:messages]] ++ options
               )

      assert [%{id: id, text: "Which residents need their medication today?"}] = one.messages
      assert id == message.id
    end

    test "and no power ruby has no conversation of their own", context do
      options = as(context, context.kim)

      assert forbidden?(Ruby.start_conversation(%{}, options))
      assert {:ok, []} = Ruby.conversations(options)
    end

    test "changes nothing in a conversation of a member", context do
      {conversation, message} = talk!(context)
      reply = reply!(context, conversation, message)

      # Kim has the power `settings` alone, and the administrator has each
      # power, the power `ruby` too.
      for user <- [context.kim, context.administrator] do
        options = as(context, user)

        assert {:error, _refused} = Ruby.say(conversation.id, "A word from above", options)
        assert forbidden?(Ruby.rename_conversation(conversation, "Seen", options))
        assert forbidden?(Ruby.remove_conversation(conversation, options))
        assert forbidden?(Ruby.rate_reply(reply, :down, options))
        assert forbidden?(Ruby.stop_reply(message, options))
      end

      assert [%{title: title}] = all(Conversation, context)
      assert title != "Seen"
      assert [_message, _reply] = all(Message, context)
    end

    test "does not find the conversations of a member among their own", context do
      {theirs, _message} = talk!(context)
      options = as(context, context.administrator)
      mine = Ruby.start_conversation!(%{}, options)

      assert {:ok, [%{id: id}]} = Ruby.conversations(options)
      assert id == mine.id
      assert {:ok, nil} = Ruby.conversation(theirs.id, options)

      # The action holds the filter itself, also where no policy is asked.
      assert [%{id: ^id}] =
               Conversation
               |> Ash.Query.for_read(:mine, %{}, [authorize?: false] ++ options)
               |> Ash.read!()
    end
  end

  describe "a removal" do
    test "deletes the conversation and its messages for real", context do
      {conversation, message} = talk!(context)
      _reply = reply!(context, conversation, message)
      {kept, _message} = talk!(context, "Another talk")

      assert :ok = Ruby.remove_conversation(conversation, as(context, context.ana))

      assert [%{id: id}] = all(Conversation, context)
      assert id == kept.id
      assert [%{conversation_id: ^id}] = all(Message, context)

      # No row is left behind a mark: the tables have no such column.
      for resource <- [Conversation, Message] do
        names = resource |> Ash.Resource.Info.attributes() |> Enum.map(& &1.name)
        refute :archived_at in names
        refute :valid_at in names
        refute function_exported?(Module.concat(resource, Version), :resource_version?, 0)
      end
    end
  end

  describe "what a record shows" do
    test "is not the words of a person, when code inspects it", context do
      {conversation, message} = talk!(context, "A private question about Biscuit")
      {:ok, read} = Ruby.conversation(conversation.id, as(context, context.ana))

      refute inspect(message) =~ "Biscuit"
      refute inspect(read) =~ "Biscuit"
    end
  end

  describe "the title of a conversation" do
    test "is the first words, on one line" do
      assert Title.of("Who is due\n  back today?") == "Who is due back today?"
      assert Title.of("  \n ") == nil
    end

    test "is cut at the end of a word" do
      text = "Which of the residents in the east paddock need their medication before noon"
      title = Title.of(text)

      assert title == "Which of the residents in the east paddock need their…"
      assert String.length(title) <= 61
      assert Title.of(String.duplicate("a", 80)) == String.duplicate("a", 60) <> "…"
    end
  end
end
