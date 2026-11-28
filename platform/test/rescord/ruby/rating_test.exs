defmodule Rescord.Ruby.RatingTest do
  @moduledoc """
  Holds "Was this answer right?" (ADR 0069): only the member of a
  conversation says Yes or No of a whole answer of it; after No they may
  say what was wrong, and send that one answer to the administrators. A
  Yes takes the words and the report back. The counts of the month count
  each answer, and only an answer that a member sent shows its words.

  Each test creates an organisation, so the tests do not run beside others.
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ClockFixtures
  import Rescord.RubyFixtures

  alias Rescord.{Accounts, Ruby}
  alias Rescord.Ruby.ScriptedModel

  setup do
    # The counts are of a month of UTC.
    clear_of_edge(:timer.hours(24))

    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    admin = [actor: administrator, tenant: organisation]
    {:ok, carer} = Accounts.define_role(%{name: "Carer", powers: [:ruby]}, admin)
    {ana_member, ana} = member!(organisation, :member, administrator)
    {:ok, _member} = Accounts.set_member_role(ana_member, carer.id, admin)
    {ben_member, ben} = member!(organisation, :member, administrator)
    {:ok, _member} = Accounts.set_member_role(ben_member, carer.id, admin)
    ruby_on!(root, admin)

    {:ok,
     root: root,
     admin: admin,
     as_ana: [actor: ana, tenant: organisation],
     as_ben: [actor: ben, tenant: organisation]}
  end

  # A whole answer of Ruby in a new conversation of the member.
  defp answer!(options, words \\ "Hay is low.") do
    conversation = Ruby.start_conversation!(%{}, options)
    Ruby.say!(conversation.id, "What is running low?", options)
    ScriptedModel.script([{:text, words}])
    Oban.drain_queue(queue: :ruby, with_safety: false)
    [_question, reply] = Ruby.messages!(conversation.id, options)
    reply
  end

  test "the member says Yes or No of a whole answer, and nobody else does", context do
    reply = answer!(context.as_ana)

    assert {:ok, %{rating: :up}} = Ruby.rate_reply(reply, :up, context.as_ana)
    assert {:ok, %{rating: :down} = reply} = Ruby.rate_reply(reply, :down, context.as_ana)

    # Another member, and an administrator who reads each conversation.
    assert {:error, %Ash.Error.Forbidden{}} = Ruby.rate_reply(reply, :up, context.as_ben)
    assert {:error, %Ash.Error.Forbidden{}} = Ruby.rate_reply(reply, :up, context.admin)

    # A message of the member has no rating.
    [question, _reply] = Ruby.messages!(reply.conversation_id, context.as_ana)
    assert {:error, error} = Ruby.rate_reply(question, :up, context.as_ana)
    assert {:source, "only a reply has a rating"} in Ruby.problems(error)
  end

  test "an answer that did not end whole has no rating", context do
    conversation = Ruby.start_conversation!(%{}, context.as_ana)
    message = Ruby.say!(conversation.id, "What is running low?", context.as_ana)
    {:ok, reply} = Rescord.Ruby.Replies.open(message, context.admin[:tenant])

    assert {:error, error} = Ruby.rate_reply(reply, :up, context.as_ana)
    assert Ruby.problems(error) == [{:state, "only a whole answer has a rating"}]
  end

  test "after No, what was wrong and the report; a Yes takes both back", context do
    reply = answer!(context.as_ana)

    # No report before No.
    assert {:error, _error} =
             Ruby.report_reply(reply, %{rating_note: "Wrong hay.", send: true}, context.as_ana)

    {:ok, reply} = Ruby.rate_reply(reply, :down, context.as_ana)

    assert {:ok, %{rating_note: "Wrong hay.", reported_at: nil}} =
             Ruby.report_reply(reply, %{rating_note: "Wrong hay."}, context.as_ana)

    assert {:ok, %{reported_at: %DateTime{}} = reply} =
             Ruby.report_reply(reply, %{rating_note: "Wrong hay.", send: true}, context.as_ana)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ruby.report_reply(reply, %{rating_note: "No.", send: true}, context.as_ben)

    # Saved again with the box ticked, the report keeps the time it was sent.
    assert {:ok, %{reported_at: sent_at}} =
             Ruby.report_reply(reply, %{rating_note: "Wrong oats.", send: true}, context.as_ana)

    assert sent_at == reply.reported_at

    assert {:ok, %{rating: :up, rating_note: nil, reported_at: nil}} =
             Ruby.rate_reply(reply, :up, context.as_ana)

    # A page that still shows the No, after a Yes in another tab: the
    # report writes nothing.
    assert {:error, _stale} =
             Ruby.report_reply(reply, %{rating_note: "Late.", send: true}, context.as_ana)

    assert {:ok, %{rating: :up, rating_note: nil, reported_at: nil}} =
             Ruby.message(reply.id, context.as_ana)
  end

  test "what was wrong is the member's own until they send the answer", context do
    kept = answer!(context.as_ana)
    {:ok, kept} = Ruby.rate_reply(kept, :down, context.as_ana)
    {:ok, _kept} = Ruby.report_reply(kept, %{rating_note: "Ours."}, context.as_ana)

    sent = answer!(context.as_ana)
    {:ok, sent} = Ruby.rate_reply(sent, :down, context.as_ana)
    {:ok, _sent} = Ruby.report_reply(sent, %{rating_note: "Theirs.", send: true}, context.as_ana)

    # The administrator reads each conversation, and not what the member
    # kept to themselves.
    assert {:ok, %{rating: :down, rating_note: %Ash.ForbiddenField{}}} =
             Ruby.message(kept.id, context.admin)

    assert {:ok, %{rating_note: "Theirs."}} = Ruby.message(sent.id, context.admin)
    assert {:ok, %{rating_note: "Ours."}} = Ruby.message(kept.id, context.as_ana)
  end

  test "the counts of the month, and the words only of an answer that was sent", context do
    right = answer!(context.as_ana, "Hay is low.")
    wrong = answer!(context.as_ana, "Oats are low.")
    sent = answer!(context.as_ben, "Nothing is low.")
    _unrated = answer!(context.as_ben)

    {:ok, _right} = Ruby.rate_reply(right, :up, context.as_ana)
    {:ok, wrong} = Ruby.rate_reply(wrong, :down, context.as_ana)
    {:ok, _wrong} = Ruby.report_reply(wrong, %{rating_note: "We have oats."}, context.as_ana)
    {:ok, sent} = Ruby.rate_reply(sent, :down, context.as_ben)

    {:ok, _sent} =
      Ruby.report_reply(sent, %{rating_note: "The straw is low.", send: true}, context.as_ben)

    assert Ruby.answers_of_month(context.admin) == %{right: 1, wrong: 2, sent: 1}

    assert [%{id: id, rating_note: "The straw is low.", response_to: %{text: question}}] =
             Ruby.reported_answers(context.admin)

    assert id == sent.id
    assert question == "What is running low?"

    # A member counts only their own, and reads no report of another.
    assert Ruby.answers_of_month(context.as_ana) == %{right: 1, wrong: 1, sent: 0}
    assert Ruby.reported_answers(context.as_ana) == []

    # An answer of another month is in no count of this one.
    next = Date.utc_today() |> Date.end_of_month() |> Date.add(1)
    assert Ruby.answers_of_month(context.admin, next) == %{right: 0, wrong: 0, sent: 0}

    # A removed conversation takes its answers, and its report, with it.
    conversation = Ruby.conversation!(sent.conversation_id, context.as_ben)
    :ok = Ruby.remove_conversation(conversation, context.as_ben)
    assert Ruby.reported_answers(context.admin) == []
  end
end
