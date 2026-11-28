defmodule Rescord.Ruby.UsageTest do
  @moduledoc """
  Holds what the assistant counts and what it refuses (ADR 0069): each
  reply adds to the use of its member, its day and its model; the use
  stays when the conversation goes; past the allowance of the month `say`
  refuses and no model is called; a conversation that is full takes no
  more; and one person says only so many messages in a minute and in a
  day.

  The model answers from a script. No test calls a provider.

  The test creates an organisation, so it does not run beside others.
  """

  use Rescord.DataCase, async: false

  import Ecto.Query, only: [from: 2]
  import ExUnit.CaptureLog
  import Rescord.AccountsFixtures
  import Rescord.ClockFixtures
  import Rescord.ResidentsFixtures
  import Rescord.RubyFixtures

  alias Rescord.{Accounts, Ruby}
  alias Rescord.Ruby.{Allowance, Message, ScriptedModel, Usage}

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    admin = [actor: administrator, tenant: organisation]

    {:ok, asker} = Accounts.define_role(%{name: "Carer", powers: [:ruby]}, admin)

    with_role = fn ->
      {member, user} = member!(organisation, :member, administrator)
      {:ok, _member} = Accounts.set_member_role(member, asker.id, admin)
      user
    end

    ana = with_role.()
    ben = with_role.()

    resident!(lists!(organisation, root), admin)
    provider = ruby_on!(root, admin)

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     admin: admin,
     ana: ana,
     ben: ben,
     as_ana: [actor: ana, tenant: organisation],
     as_ben: [actor: ben, tenant: organisation],
     provider: provider}
  end

  defp ask!(context, text \\ "Who is in our care?") do
    conversation = Ruby.start_conversation!(%{}, context.as_ana)
    message = Ruby.say!(conversation.id, text, context.as_ana)
    {conversation, message}
  end

  defp work!, do: Oban.drain_queue(queue: :ruby, with_safety: false)

  defp jobs, do: Rescord.Repo.all(from(job in Oban.Job, where: job.queue == "ruby"))

  defp rows(context), do: Ash.read!(Usage, tenant: context.organisation, authorize?: false)

  defp reply_of(context, conversation),
    do: conversation.id |> Ruby.messages!(context.as_ana) |> List.last()

  # The allowance of the organisation, in whole US cents. A save of the
  # settings with Ruby on names the place again, as the page does.
  defp allow!(context, cents) do
    [offer] = Ruby.offers(context.admin)

    {:ok, _settings} =
      Ruby.save_settings(
        %{enabled: true, provider_id: offer.id, agreed_to: offer.place_key, allowance: cents},
        context.admin
      )
  end

  describe "the use" do
    test "gets the tokens and the price of each reply, in one row for a member, a day and a model",
         context do
      # The row is of the UTC day of the reply.
      clear_of_edge(:timer.hours(24))

      ScriptedModel.script([
        {:tool, "find_residents", %{}},
        {:text, "Biscuit is in your care."},
        {:text, "Yes."}
      ])

      {conversation, _message} = ask!(context)
      work!()

      # Two requests of 1,000 tokens in and 50 out, at the prices of Opus.
      assert [row] = rows(context)
      assert row.day == Date.utc_today()
      assert row.user_id == context.ana.id
      assert row.model == "claude-opus-5-5"

      assert Map.take(row, Usage.counts()) == %{
               replies: 1,
               requests: 2,
               input_tokens: 2_000,
               cache_read_tokens: 0,
               cache_write_tokens: 0,
               output_tokens: 100,
               cost_microdollars: 10_000,
               failed: 0,
               refused: 0,
               stopped: 0
             }

      Ruby.say!(conversation.id, "Is that all?", context.as_ana)
      work!()

      assert [row] = rows(context)
      assert {row.replies, row.requests, row.input_tokens} == {2, 3, 3_000}
      assert {row.output_tokens, row.cost_microdollars} == {150, 15_000}
      assert Allowance.used(context.organisation) == 15_000
    end

    test "has a row for each member", context do
      ScriptedModel.script([{:text, "Yes."}, {:text, "No."}])
      ask!(context)
      conversation = Ruby.start_conversation!(%{}, context.as_ben)
      Ruby.say!(conversation.id, "And for me?", context.as_ben)
      work!()

      assert [context.ana.id, context.ben.id] |> Enum.sort() ==
               context |> rows() |> Enum.map(& &1.user_id) |> Enum.sort()

      assert Allowance.used(context.organisation) == 2 * 5_000
    end

    test "counts a refusal and a reply that failed after its requests, and they are billed",
         context do
      ScriptedModel.script([{:refusal, "I can't help with that."}])
      ask!(context)
      work!()

      assert [%{replies: 1, refused: 1, failed: 0, cost_microdollars: 5_000}] = rows(context)

      ScriptedModel.script(List.duplicate({:tool, "find_residents", %{}}, 8))
      ask!(context)
      capture_log(fn -> work!() end)

      assert [%{replies: 2, requests: 9, refused: 1, failed: 1, cost_microdollars: 45_000}] =
               rows(context)
    end

    test "has nothing of a reply that sent no request", context do
      # The library gave an error before the stream.
      ScriptedModel.script([{:error, :timeout}])
      ask!(context)
      capture_log(fn -> work!() end)

      # The member stopped the reply before its job started.
      {_conversation, message} = ask!(context)
      {:ok, _message} = Ruby.stop_reply(message, context.as_ana)
      work!()

      assert rows(context) == []
      assert Allowance.used(context.organisation) == 0
    end

    test "stays when its conversation is deleted for real", context do
      ScriptedModel.script([{:text, "Yes."}])
      {conversation, _message} = ask!(context)
      work!()

      :ok = Ruby.remove_conversation(conversation, context.as_ana)

      assert Ash.read!(Message, tenant: context.organisation, authorize?: false) == []
      assert [%{replies: 1, cost_microdollars: 5_000}] = rows(context)
      assert Allowance.used(context.organisation) == 5_000
    end

    test "is a sum of one month of the calendar", context do
      tenant = context.organisation
      counts = %{replies: 1, requests: 1, cost_microdollars: 7_000}

      Allowance.add!(context.ana.id, "a-model", counts, tenant, ~D[2026-10-31])
      Allowance.add!(context.ana.id, "a-model", counts, tenant, ~D[2026-11-01])
      Allowance.add!(context.ana.id, "a-model", counts, tenant, ~D[2026-11-30])
      # The same member, day and model: the same row, with the sum.
      Allowance.add!(context.ana.id, "a-model", counts, tenant, ~D[2026-11-30])
      Allowance.add!(context.ana.id, "a-model", counts, tenant, ~D[2026-12-01])

      assert Allowance.used(tenant, ~D[2026-11-15]) == 3 * 7_000
      assert Allowance.used(tenant, ~D[2026-10-01]) == 7_000
      assert Allowance.used(tenant, ~D[2027-01-01]) == 0
      assert length(rows(context)) == 4
    end

    test "is read by a person with the power settings and by a root user, and by no other member",
         context do
      ScriptedModel.script([{:text, "Yes."}])
      ask!(context)
      work!()

      assert [_row] = Ash.read!(Usage, context.admin)
      assert [_row] = Ash.read!(Usage, actor: context.root, tenant: context.organisation)
      assert Ash.read!(Usage, context.as_ana) == []

      refute Ash.can?({Usage, :add}, context.administrator, tenant: context.organisation)
    end
  end

  describe "the allowance of a month" do
    test "past it, say refuses with the reason, and no model is called", context do
      # The allowance is of the UTC month of each reply.
      clear_of_edge(:timer.hours(24))

      # One cent: a reply of 5,000 millionths leaves room, and two do not.
      allow!(context, 1)
      ScriptedModel.script([{:text, "Yes."}, {:text, "Yes."}])

      {conversation, _message} = ask!(context)
      work!()
      assert Allowance.room?(context.organisation)

      Ruby.say!(conversation.id, "And now?", context.as_ana)
      work!()
      refute Allowance.room?(context.organisation)

      assert {:error, error} = Ruby.say(conversation.id, "Once more?", context.as_ana)
      assert Ruby.refusal(error) == :allowance
      assert [{:text, "the allowance of the month is used"}] = Ruby.problems(error)

      # Nothing was saved, no job waits, and the model got two requests.
      assert length(Ruby.messages!(conversation.id, context.as_ana)) == 4
      assert Enum.all?(jobs(), &(&1.state == "completed"))
      assert length(ScriptedModel.requests()) == 2

      # The member still reads the conversation, and Ruby is still on.
      assert Ruby.available?(context.ana, context.organisation)

      # The next month has room, and a larger allowance has too.
      assert Allowance.room?(context.organisation, Date.shift(Date.utc_today(), month: 1))
      allow!(context, 2)
      assert {:ok, _message} = Ruby.say(conversation.id, "Once more?", context.as_ana)
    end

    test "of nothing takes no message", context do
      allow!(context, 0)
      conversation = Ruby.start_conversation!(%{}, context.as_ana)

      assert {:error, error} = Ruby.say(conversation.id, "Anyone?", context.as_ana)
      assert Ruby.refusal(error) == :allowance
      assert jobs() == []
    end
  end

  describe "the size of a conversation" do
    test "is kept with each reply, as the provider reported it", context do
      ScriptedModel.script([{:tool, "find_residents", %{}}, {:text, "Biscuit."}])
      {conversation, _message} = ask!(context)
      work!()

      # The prompt of the last request and its answer.
      reply = reply_of(context, conversation)
      assert Ash.load!(reply, [], authorize?: false).prompt_tokens == 1_000 + 50
    end

    test "a conversation that is full takes no more messages", context do
      ScriptedModel.script([{:text, "Yes."}, {:text, "Yes."}])
      {conversation, _message} = ask!(context)
      work!()

      # The limit of a request of this provider is 60,000 tokens.
      reply = reply_of(context, conversation)
      # The reply is complete, so it takes no write of Ruby: the test sets the
      # count of its tokens.
      Ash.Seed.update!(reply, %{prompt_tokens: 59_990})

      # 31 bytes are 11 tokens, at three bytes for a token.
      long = String.duplicate("a", 31)
      assert {:error, error} = Ruby.say(conversation.id, long, context.as_ana)
      assert Ruby.refusal(error) == :too_long
      assert [{:text, "this conversation is full: start a new one"}] = Ruby.problems(error)

      # 30 bytes are 10 tokens, and fit.
      assert {:ok, _message} =
               Ruby.say(conversation.id, String.duplicate("a", 30), context.as_ana)
    end

    test "inside a reply, a tool result that would make the next request too long ends it",
         context do
      # The first request reports a prompt just below the limit, and asks
      # for a tool. Its result is what the next request would add.
      ScriptedModel.script([
        {:usage, %{input_tokens: 59_940, output_tokens: 50}, {:tool, "find_residents", %{}}},
        {:text, "This is never asked for."}
      ])

      {conversation, _message} = ask!(context)

      log = capture_log(fn -> work!() end)
      assert log =~ "Ruby: a reply failed (too_long)"

      assert %{state: :failed, reason: :too_long} = reply = reply_of(context, conversation)
      assert [_one_request] = ScriptedModel.requests()

      # The conversation is full now, and the request that went is counted.
      assert Ash.load!(reply, [], authorize?: false).prompt_tokens > 60_000
      assert {:error, error} = Ruby.say(conversation.id, "And now?", context.as_ana)
      assert Ruby.refusal(error) == :too_long
      assert [%{requests: 1, failed: 1, input_tokens: 59_940}] = rows(context)
    end
  end

  describe "the rate of one person" do
    # Each message is in a conversation of its own, so that none waits for
    # a reply. The counts are under the id of the person, which is new in
    # each test.
    defp say_in_new(options) do
      conversation = Ruby.start_conversation!(%{}, options)
      Ruby.say(conversation.id, "Anyone?", options)
    end

    test "is 6 messages a minute: the seventh is refused, and another person is not", context do
      # The seven messages are in one window of a minute.
      clear_of_edge(:timer.minutes(1), :timer.seconds(5))

      for _ <- 1..6, do: assert({:ok, _message} = say_in_new(context.as_ana))

      assert {:error, error} = say_in_new(context.as_ana)
      assert Ruby.refusal(error) == :rate
      assert [{:text, "wait a moment before you ask again"}] = Ruby.problems(error)
      assert length(jobs()) == 6

      assert {:ok, _message} = say_in_new(context.as_ben)
    end

    test "is 120 messages a day", context do
      clear_of_edge(:timer.hours(24))

      # 119 of the day are used, with none of this minute.
      key = "ruby/say/day/" <> context.ana.id

      for count <- 1..119,
          do: {:allow, ^count} = Rescord.RateLimit.hit(key, :timer.hours(24), 120)

      assert {:ok, _message} = say_in_new(context.as_ana)

      assert {:error, error} = say_in_new(context.as_ana)
      assert Ruby.refusal(error) == :rate
    end
  end

  describe "the metrics of the server" do
    test "get one event for a reply, with its counts and no organisation, member or model",
         context do
      test = self()

      :telemetry.attach(
        "usage-test",
        [:rescord, :ruby, :reply, :stop],
        fn _event, measurements, metadata, _config ->
          send(test, {:reply, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach("usage-test") end)

      ScriptedModel.script([{:text, "Yes."}])
      ask!(context)
      work!()

      assert_receive {:reply, measurements, metadata}

      assert measurements == %{
               requests: 1,
               input_tokens: 1_000,
               cache_read_tokens: 0,
               cache_write_tokens: 0,
               output_tokens: 50,
               cost_microdollars: 5_000
             }

      assert metadata == %{state: :complete, reason: nil}
    end
  end
end
