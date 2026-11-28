defmodule Rescord.Ruby.TidyTest do
  @moduledoc """
  Holds the job that keeps the conversations of Ruby to what may stay
  (ADR 0069): the days of the settings, the conversations of a member who
  left, and a reply that lost its job. The job takes the time as an
  argument, so the tests run it on day 89 and on day 91.

  Each test creates an organisation, so the tests do not run beside others.
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.RubyFixtures

  alias Rescord.{Accounts, Ruby}
  alias Rescord.Ruby.{Conversation, Events, Replies}
  alias Rescord.Ruby.Workers.Tidy

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    admin = [actor: administrator, tenant: organisation]
    {kim_member, kim} = member!(organisation, :administrator, root)
    ruby_on!(root, admin)

    {:ok,
     root: root,
     organisation: organisation,
     admin: admin,
     kim_member: kim_member,
     as_kim: [actor: kim, tenant: organisation]}
  end

  # A conversation whose last message was at this time, with a message
  # when there are words.
  defp conversation!(options, at, words \\ nil) do
    conversation = Ruby.start_conversation!(%{}, options)
    if words, do: Ruby.say!(conversation.id, words, options)

    conversation
    |> Ash.Changeset.for_update(:touch, %{last_message_at: at},
      tenant: options[:tenant],
      authorize?: false
    )
    |> Ash.update!()
  end

  defp ids(options), do: options |> Ruby.conversations!() |> Enum.map(& &1.id) |> Enum.sort()

  test "a conversation stays for the days of the settings after its last message", context do
    last = ~U[2026-09-01 10:00:00.000000Z]
    old = conversation!(context.admin, last, "Who is on medication today?")
    newer = conversation!(context.admin, DateTime.add(last, 2, :day))

    # Day 89: both stay.
    assert %{old: 0} = Tidy.tidy(context.organisation, DateTime.add(last, 89, :day))
    assert ids(context.admin) == Enum.sort([old.id, newer.id])

    # Day 91: the old one goes, with its messages.
    assert %{old: 1} = Tidy.tidy(context.organisation, DateTime.add(last, 91, :day))
    assert ids(context.admin) == [newer.id]
    assert {:ok, []} = Ruby.messages(old.id, context.admin)

    # The days are a setting of the organisation.
    [offer] = Ruby.offers(context.admin)

    {:ok, _settings} =
      Ruby.save_settings(
        %{enabled: true, provider_id: offer.id, agreed_to: offer.place_key, retention_days: 30},
        context.admin
      )

    assert %{old: 1} = Tidy.tidy(context.organisation, DateTime.add(last, 33, :day))
    assert ids(context.admin) == []
  end

  test "the job takes the time as an argument", context do
    last = ~U[2026-09-01 10:00:00.000000Z]
    conversation!(context.admin, last)

    now = last |> DateTime.add(91, :day) |> DateTime.to_iso8601()
    assert :ok = Tidy.perform(%Oban.Job{args: %{"now" => now}})
    assert ids(context.admin) == []
  end

  test "the conversations of a person who is no member any more go", context do
    now = DateTime.utc_now()
    theirs = conversation!(context.as_kim, now)
    mine = conversation!(context.admin, now)

    assert %{left: 0} = Tidy.tidy(context.organisation, now)
    assert ids(context.as_kim) == [theirs.id]

    :ok =
      Accounts.remove_member(context.kim_member,
        actor: context.root,
        tenant: context.organisation
      )

    assert %{left: 1} = Tidy.tidy(context.organisation, now)

    remaining =
      Conversation
      |> Ash.read!(tenant: context.organisation, authorize?: false)
      |> Enum.map(& &1.id)

    assert remaining == [mine.id]
  end

  test "a reply that has not changed for six minutes fails, and its page hears it", context do
    conversation = conversation!(context.admin, DateTime.utc_now())
    message = Ruby.say!(conversation.id, "What is running low?", context.admin)
    {:ok, reply} = Replies.open(message, context.organisation)
    :ok = Events.listen(conversation.id)

    # Five minutes later it may still be on its way.
    assert %{hung: 0} =
             Tidy.tidy(context.organisation, DateTime.add(reply.updated_at, 5, :minute))

    assert {:ok, %{state: :streaming}} = Ruby.message(reply.id, context.admin)

    assert %{hung: 1} =
             Tidy.tidy(context.organisation, DateTime.add(reply.updated_at, 7, :minute))

    assert {:ok, %{state: :failed, reason: :unknown}} = Ruby.message(reply.id, context.admin)
    reply_id = reply.id
    assert_receive {:ruby, :reply, ^reply_id, :failed}

    # The conversation takes the next message.
    assert {:ok, _message} = Ruby.say(conversation.id, "And now?", context.admin)
  end

  test "a reply that ended in between keeps its end, and a late write of its job is gone",
       context do
    conversation = conversation!(context.admin, DateTime.utc_now())
    message = Ruby.say!(conversation.id, "What is running low?", context.admin)
    {:ok, reply} = Replies.open(message, context.organisation)
    later = DateTime.add(reply.updated_at, 7, :minute)

    # The job ended the reply before Tidy came: Tidy writes nothing.
    :ok = Replies.close(reply, %{text: "Hay.", state: :complete}, context.organisation)
    assert %{hung: 0} = Tidy.tidy(context.organisation, later)
    assert {:ok, %{state: :complete, text: "Hay."}} = Ruby.message(reply.id, context.admin)

    # Tidy ended another reply first: the job that comes later writes
    # nothing, and hears that its reply is gone.
    other = Ruby.say!(conversation.id, "And the oats?", context.admin)
    {:ok, hung} = Replies.open(other, context.organisation)
    assert %{hung: 1} = Tidy.tidy(context.organisation, DateTime.add(hung.updated_at, 7, :minute))
    assert :gone = Replies.save(hung, %{text: "Oats"}, context.organisation)
    assert :gone = Replies.close(hung, %{text: "Oats.", state: :complete}, context.organisation)
    assert {:ok, %{state: :failed, reason: :unknown}} = Ruby.message(hung.id, context.admin)
  end

  test "a message whose job died before its reply gets a failed reply", context do
    conversation = conversation!(context.admin, DateTime.utc_now())
    message = Ruby.say!(conversation.id, "What is running low?", context.admin)
    :ok = Events.listen(conversation.id)

    assert %{hung: 0} =
             Tidy.tidy(context.organisation, DateTime.add(message.inserted_at, 5, :minute))

    assert %{hung: 1} =
             Tidy.tidy(context.organisation, DateTime.add(message.inserted_at, 7, :minute))

    assert {:ok, [_message, reply]} = Ruby.messages(conversation.id, context.admin)
    assert %{source: :ruby, state: :failed, reason: :unknown} = reply
    reply_id = reply.id
    assert_receive {:ruby, :reply, ^reply_id, :failed}

    # A job that still comes finds the reply there, and does nothing.
    assert :taken = Replies.open(message, context.organisation)
    assert {:ok, _message} = Ruby.say(conversation.id, "And now?", context.admin)
  end
end
