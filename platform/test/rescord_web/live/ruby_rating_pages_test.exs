defmodule RescordWeb.RubyRatingPagesTest do
  @moduledoc """
  Holds "Was this answer right?" on the pages (ADR 0069): the member says
  Yes or No below a whole answer, says after No what was wrong, and may
  send the answer to the administrators. The settings of Ruby count what
  the members said, and show the words only of an answer that a member
  sent. The tests find what a person finds (ADR 0107).

  No test calls a provider: the scripted model writes each answer.

  Each test creates an organisation, so the tests do not run beside others.
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Rescord.AccountsFixtures
  import Rescord.ClockFixtures
  import Rescord.RubyFixtures

  alias Rescord.{Accounts, Ruby}
  alias Rescord.Ruby.ScriptedModel

  setup context do
    # The counts of the settings are of a month of UTC.
    clear_of_edge(:timer.hours(24))

    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    admin = [actor: administrator, tenant: organisation]
    {:ok, carer} = Accounts.define_role(%{name: "Carer", powers: [:ruby]}, admin)
    {ana_member, ana} = member!(organisation, :member, administrator)
    {:ok, _member} = Accounts.set_member_role(ana_member, carer.id, admin)
    ruby_on!(root, admin)

    {:ok,
     organisation: organisation,
     administrator: administrator,
     ana: ana,
     as_ana: [actor: ana, tenant: organisation],
     ruby: ~p"/o/#{organisation.short_name}/ruby",
     settings: ~p"/o/#{organisation.short_name}/settings/ruby",
     conn: sign_in(context.conn, ana)}
  end

  # A whole answer in a new conversation of Ana.
  defp answer!(context, words) do
    conversation = Ruby.start_conversation!(%{}, context.as_ana)
    Ruby.say!(conversation.id, "What is running low?", context.as_ana)
    ScriptedModel.script([{:text, words}])
    Oban.drain_queue(queue: :ruby, with_safety: false)
    [_question, reply] = Ruby.messages!(conversation.id, context.as_ana)
    {conversation, reply}
  end

  defp answer, do: main() |> article("Ruby")

  describe "below a whole answer" do
    test "Yes is pressed at once; No asks what was wrong, and nothing more", context do
      {conversation, reply} = answer!(context, "Hay is low.")

      session =
        context.conn
        |> visit(context.ruby <> "/" <> conversation.id)
        |> click(answer() |> button("Yes"))
        |> assert_has("button[aria-pressed=\"true\"]", text: "Yes")
        |> refute_has(answer() |> field("What was wrong?"))

      assert {:ok, %{rating: :up}} = Ruby.message(reply.id, context.as_ana)

      session
      |> click(answer() |> button("No"))
      |> assert_has("button[aria-pressed=\"true\"]", text: "No")
      |> fill_in("What was wrong?", with: "We have plenty of hay.")
      |> click(answer() |> button("Save what was wrong"))
      |> assert_has(status(), text: "What was wrong is saved.")

      assert {:ok, %{rating: :down, rating_note: "We have plenty of hay.", reported_at: nil}} =
               Ruby.message(reply.id, context.as_ana)
    end

    test "the box sends the answer to the administrators", context do
      {conversation, reply} = answer!(context, "Oats are low.")

      context.conn
      |> visit(context.ruby <> "/" <> conversation.id)
      |> click(answer() |> button("No"))
      |> fill_in("What was wrong?", with: "We have oats.")
      |> check(
        "Send this question and its answer, and what Ruby read for it, to the administrators"
      )
      |> click(answer() |> button("Save what was wrong"))
      |> assert_has(status(), text: "The answer is sent to the administrators.")
      |> assert_has(answer(), text: "You sent this answer to the administrators.")

      assert {:ok, %{reported_at: %DateTime{}}} = Ruby.message(reply.id, context.as_ana)
    end
  end

  describe "the settings of Ruby" do
    setup context do
      {_conversation, said} = answer!(context, "Hay is low.")
      {:ok, said} = Ruby.rate_reply(said, :down, context.as_ana)

      {:ok, _said} =
        Ruby.report_reply(said, %{rating_note: "We keep this to us."}, context.as_ana)

      {_conversation, sent} = answer!(context, "Oats are low.")
      {:ok, sent} = Ruby.rate_reply(sent, :down, context.as_ana)

      {:ok, _sent} =
        Ruby.report_reply(sent, %{rating_note: "We have oats.", send: true}, context.as_ana)

      {_conversation, right} = answer!(context, "Straw is low.")
      {:ok, _right} = Ruby.rate_reply(right, :up, context.as_ana)

      {:ok, admin_conn: build_conn() |> sign_in(context.administrator)}
    end

    test "count what the members said, and show only the answer that was sent", context do
      month = Date.utc_today() |> Date.beginning_of_month() |> RescordWeb.Locale.month()
      answers = main() |> region("Was each answer right?")

      context.admin_conn
      |> visit(context.settings)
      |> assert_has(answers,
        text:
          "In #{month}, members said that 1 answer was right and 2 answers were not right. " <>
            "1 of those was sent to you."
      )
      |> assert_has(
        answers
        |> article(~r/^Sent by #{Regex.escape(to_string(context.ana.email))}/)
      )
      |> assert_has(answers, text: "Oats are low.")
      |> assert_has(answers, text: "What was wrong: We have oats.")
      |> assert_has(answers, text: "The question: What is running low?")
      # The words of an answer that nobody sent stay in its conversation.
      |> refute_has(answers, text: "We keep this to us.")
      |> refute_has(answers, text: "Hay is low.")
      |> refute_has(answers, text: "Straw is low.")
    end

    test "are not there for the member", context do
      context.conn
      |> visit(context.settings)
      |> refute_has(main() |> region("Was each answer right?"))
      |> refute_has(main(), text: "We have oats.")
    end
  end
end
