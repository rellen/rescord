defmodule Rescord.Ruby.RepliesTest do
  @moduledoc """
  Holds the reply of the assistant (ADR 0069): `say` puts a job in the
  queue `ruby`, and the job writes the reply as the member who asked, in
  the organisation of the question.

  The first part runs with the model that answers from a script. The
  second part runs the real ReqLLM against a server on this machine that
  plays the provider, for what a script skips: the errors of HTTP, a
  connection that breaks, and a stop in the middle of an answer. No test
  calls a provider.

  The job runs in the process of the test (`Oban.drain_queue/1`), so the
  script of the test reaches it, and a fault in the job fails the test.

  The test creates an organisation, so it does not run beside others.
  """

  use Rescord.DataCase, async: false

  import Ecto.Query, only: [from: 2]
  import ExUnit.CaptureLog
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.RubyFixtures

  alias Rescord.{Accounts, FakeAnthropic, Ruby}
  alias Rescord.Ruby.{Message, Prompt, Replies, ScriptedModel}

  @zone "Australia/Brisbane"

  # A word that is in no line of the code, for the tests that hold what
  # the log and the job do not keep.
  @marker "quokkazanzibar"

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek", @zone)
    {_, administrator} = member!(organisation, :administrator, root)
    admin = [actor: administrator, tenant: organisation]

    {:ok, asker} = Accounts.define_role(%{name: "Carer", powers: [:ruby]}, admin)
    {ana_member, ana} = member!(organisation, :member, administrator)
    {:ok, _member} = Accounts.set_member_role(ana_member, asker.id, admin)

    lists = lists!(organisation, root)
    biscuit = resident!(lists, admin)
    provider = ruby_on!(root, admin)

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     admin: admin,
     ana_member: ana_member,
     ana: ana,
     as_ana: [actor: ana, tenant: organisation],
     lists: lists,
     biscuit: biscuit,
     provider: provider}
  end

  # Ana starts a conversation and says a thing in it.
  defp ask!(context, text \\ "Who is in our care?") do
    conversation = Ruby.start_conversation!(%{}, context.as_ana)
    message = Ruby.say!(conversation.id, text, context.as_ana)
    {conversation, message}
  end

  # Runs the jobs of the queue in this process. A fault fails the test.
  defp work!, do: Oban.drain_queue(queue: :ruby, with_safety: false)

  defp jobs, do: Rescord.Repo.all(from(job in Oban.Job, where: job.queue == "ruby"))

  defp talk(context, conversation), do: Ruby.messages!(conversation.id, context.as_ana)

  defp reply_of(context, conversation), do: context |> talk(conversation) |> List.last()

  defp text_of(%{content: content}) do
    content |> Enum.filter(&(&1.type == :text)) |> Enum.map_join(& &1.text)
  end

  describe "a question of a member" do
    test "gets an answer from a job: a tool call and the words, as that member", context do
      # A resident of another refuge, which the answer must not hold.
      banksia = organisation!(context.root, "Banksia Rise", @zone)
      {_, keeper} = member!(banksia, :administrator, context.root)
      there = [actor: keeper, tenant: banksia]
      resident!(lists!(banksia, context.root), there, %{name: "Clover"})

      ScriptedModel.script([{:tool, "find_residents", %{}}, {:text, "Biscuit is in your care."}])

      {conversation, message} = ask!(context)

      # The job holds who and where, and no word of the question.
      assert [job] = jobs()
      assert job.worker == "Rescord.Ruby.Message.Workers.Respond"
      assert job.max_attempts == 1
      assert job.args["primary_key"] == %{"id" => message.id}
      assert job.args["actor"] == %{"type" => "user", "id" => context.ana.id}
      assert job.args["tenant"] == "org_" <> context.organisation.id
      refute inspect(job.args) =~ "care"

      assert %{success: 1, failure: 0} = work!()

      assert [said, reply] = talk(context, conversation)
      assert said.id == message.id
      assert reply.source == :ruby
      assert reply.response_to_id == message.id
      assert reply.owner_id == context.ana.id
      assert {reply.state, reply.reason} == {:complete, nil}
      assert reply.text == "Biscuit is in your care."

      # What the page does not show: the model, the tokens of the two
      # requests and their price at the prices of Opus, and the hash of the
      # prompt and the tools.
      reply = Ash.load!(reply, [], authorize?: false)
      assert reply.model == "claude-opus-5-5"

      assert reply.usage == %{
               "input" => 2_000,
               "cache_read" => 0,
               "cache_write" => 0,
               "output" => 100
             }

      assert reply.cost_microdollars == 2_000 * 4 + 100 * 20
      assert is_binary(reply.prompt_fingerprint)

      # The parts hold the call and its result, as the model gets them again.
      types = Enum.map(reply.parts, & &1["type"])
      assert "tool_call" in types
      assert "tool_result" in types
      assert List.last(types) == "text"

      # The first request: the one system prompt, and the question behind
      # its header.
      assert [first, second] = ScriptedModel.requests()
      assert [system, question] = first.messages
      assert system.role == :system
      assert text_of(system) == Prompt.system()
      assert question.role == :user
      assert text_of(question) == said.header <> "Who is in our care?"

      assert Enum.map(first.opts[:tools], & &1.name) |> Enum.sort() ==
               ["find_residents", "get_task", "tasks_for_day"]

      # The second request has the result of the tool: the resident of this
      # refuge, and none of the other one.
      result = List.last(second.messages)
      assert result.role == :tool
      assert text_of(result) =~ "Biscuit"
      refute text_of(result) =~ "Clover"
    end

    test "the next question gets the whole talk again, and the header one time", context do
      ScriptedModel.script([
        {:tool, "find_residents", %{}},
        {:text, "Biscuit is in your care."},
        {:text, "No Clover is in the records."}
      ])

      {conversation, first} = ask!(context)
      work!()

      second = Ruby.say!(conversation.id, "And Clover?", context.as_ana)
      assert second.header == nil
      work!()

      assert [_said, _reply, _again, reply] = talk(context, conversation)
      assert reply.text == "No Clover is in the records."

      assert [_one, _two, request] = ScriptedModel.requests()

      assert Enum.map(request.messages, & &1.role) ==
               [:system, :user, :assistant, :tool, :assistant, :user]

      [_system, question, call, _result, answer, again] = request.messages
      assert text_of(question) == first.header <> "Who is in our care?"
      assert [%{function: %{name: "find_residents"}}] = call.tool_calls
      assert text_of(answer) == "Biscuit is in your care."
      assert text_of(again) == "And Clover?"
    end

    test "a job that runs a second time makes no second reply, and asks no model", context do
      ScriptedModel.script([{:text, "Biscuit."}])
      {conversation, message} = ask!(context)
      assert %{success: 1} = work!()

      # The same trigger again, as a job that Oban runs twice.
      AshOban.run_trigger(message, :respond,
        actor: context.ana,
        tenant: "org_" <> context.organisation.id
      )

      work!()

      assert [_said, %{text: "Biscuit."}] = talk(context, conversation)
      assert [_one_request] = ScriptedModel.requests()

      # And the row of the reply is taken, whoever asks for it.
      assert Replies.open(message, context.organisation) == :taken
    end

    test "has a header with the rescue, the role, the day and the zone, and no person",
         context do
      {_conversation, message} = ask!(context)
      today = Accounts.local_date(context.organisation, DateTime.utc_now())

      assert message.header ==
               Prompt.header(%{
                 organisation: "Wattle Creek",
                 role: "Carer",
                 today: today,
                 time_zone: @zone
               })

      assert message.header =~ "rescue: Wattle Creek\nrole: Carer\ntoday: "
      refute message.header =~ to_string(context.ana.email)
      refute message.header =~ context.ana.id
    end

    test "names the record that the conversation is about in its header", context do
      about = "resident:" <> context.biscuit.id
      conversation = Ruby.start_conversation!(%{about: about}, context.as_ana)
      message = Ruby.say!(conversation.id, "What does he need?", context.as_ana)

      assert message.header =~ "\nabout: #{about}\n</context>"
    end

    test "of a later day has the new day, and one of the same day has none", context do
      conversation = Ruby.start_conversation!(%{}, context.as_ana)

      # A question and its answer of two days ago.
      said =
        Ash.Seed.seed!(
          Message,
          %{
            conversation_id: conversation.id,
            owner_id: context.ana.id,
            source: :user,
            text: "An old question",
            header: "<context>\nrescue: Wattle Creek\n</context>\n\n",
            inserted_at: DateTime.add(DateTime.utc_now(), -2, :day)
          },
          tenant: context.organisation
        )

      Ash.Seed.seed!(
        Message,
        %{
          conversation_id: conversation.id,
          owner_id: context.ana.id,
          response_to_id: said.id,
          source: :ruby,
          state: :complete,
          text: "An old answer"
        },
        tenant: context.organisation
      )

      ScriptedModel.script([{:text, "Yes."}])
      today = Accounts.local_date(context.organisation, DateTime.utc_now())

      later = Ruby.say!(conversation.id, "A new question", context.as_ana)
      assert later.header == Prompt.day_note(today)
      work!()

      same_day = Ruby.say!(conversation.id, "One more", context.as_ana)
      assert same_day.header == nil
    end
  end

  describe "the member of a job" do
    alias Rescord.Ruby.ActorPersister

    test "is kept as an id, and comes back with the root level off", context do
      assert ActorPersister.store(context.root) == %{"type" => "user", "id" => context.root.id}

      assert {:ok, actor} = ActorPersister.lookup(ActorPersister.store(context.root))
      assert actor.id == context.root.id
      assert actor.root? == false
    end

    test "who is gone comes back as nobody" do
      gone = %{"type" => "user", "id" => Ash.UUID.generate()}

      assert ActorPersister.lookup(gone) == {:ok, nil}
      assert ActorPersister.lookup(%{"type" => "user", "id" => "no id"}) == {:ok, nil}
      assert ActorPersister.lookup(nil) == {:ok, nil}
    end

    test "is the owner of the message, or the job writes a failed reply", context do
      ScriptedModel.script([])
      {conversation, message} = ask!(context)

      # A job of the same message with another person in it.
      Rescord.Repo.delete_all(from(job in Oban.Job, where: job.queue == "ruby"))

      AshOban.run_trigger(message, :respond,
        actor: context.administrator,
        tenant: "org_" <> context.organisation.id
      )

      capture_log(fn -> work!() end)

      assert %{state: :failed, reason: :unknown} = reply_of(context, conversation)
      assert ScriptedModel.requests() == []
    end
  end

  describe "a conversation" do
    test "takes one message at a time", context do
      ScriptedModel.script([{:text, "Biscuit."}, {:text, "Yes."}])
      {conversation, _message} = ask!(context)

      assert {:error, error} = Ruby.say(conversation.id, "And now?", context.as_ana)
      assert [{:text, "Ruby is still answering" <> _}] = Ruby.problems(error)
      assert [_one] = jobs()

      work!()
      assert {:ok, _message} = Ruby.say(conversation.id, "And now?", context.as_ana)
    end

    test "takes no more messages after the provider refused to answer in it", context do
      ScriptedModel.script([{:refusal, "I can't help with that."}])
      {conversation, _message} = ask!(context)
      work!()

      assert %{state: :failed, reason: :refused} = reply_of(context, conversation)

      assert {:error, error} = Ruby.say(conversation.id, "Again?", context.as_ana)
      assert [{:text, "this conversation takes no more messages" <> _}] = Ruby.problems(error)
    end

    test "takes no message where Ruby is off, and no job starts", context do
      conversation = Ruby.start_conversation!(%{}, context.as_ana)
      {:ok, _settings} = Ruby.save_settings(%{enabled: false}, context.admin)

      assert {:error, error} = Ruby.say(conversation.id, "Anyone?", context.as_ana)
      assert [{:text, "Ruby is off here"}] = Ruby.problems(error)
      assert talk(context, conversation) == []
      assert jobs() == []
    end
  end

  describe "a reply that does not go well" do
    test "is stopped before the job starts: nothing is sent", context do
      ScriptedModel.script([])
      {conversation, message} = ask!(context)
      {:ok, _message} = Ruby.stop_reply(message, context.as_ana)

      assert %{success: 1} = work!()

      assert %{state: :stopped, reason: nil, text: ""} = reply = reply_of(context, conversation)
      assert Ash.load!(reply, [], authorize?: false).cost_microdollars == 0
      assert ScriptedModel.requests() == []
    end

    test "fails with no request when the member lost the power before the job ran", context do
      ScriptedModel.script([])
      {conversation, _message} = ask!(context)

      {:ok, reader} = Accounts.define_role(%{name: "Reader", powers: []}, context.admin)
      {:ok, _member} = Accounts.set_member_role(context.ana_member, reader.id, context.admin)

      log = capture_log(fn -> work!() end)
      assert log =~ "Ruby: a reply failed (unknown)"

      # Ana reads her conversations no more. The row says what happened.
      assert [_said, %{state: :failed, reason: :unknown, text: ""}] =
               Ash.read!(Message, tenant: context.organisation, authorize?: false)

      assert ScriptedModel.requests() == []
      assert Ruby.messages!(conversation.id, context.as_ana) == []
    end

    test "fails with no request when Ruby was turned off before the job ran", context do
      ScriptedModel.script([])
      {conversation, _message} = ask!(context)
      {:ok, _settings} = Ruby.save_settings(%{enabled: false}, context.admin)

      capture_log(fn -> work!() end)

      assert %{state: :failed, reason: :unknown} = reply_of(context, conversation)
      assert ScriptedModel.requests() == []
    end

    test "fails as a server with no Ruby when the key of the provider is gone", context do
      ScriptedModel.script([])
      {conversation, _message} = ask!(context)

      # The secret of the server changed: the vault cannot open the key.
      secrets!(String.duplicate("another secret ", 5))

      log = capture_log(fn -> work!() end)
      assert log =~ "[error] Ruby: a reply failed (key_refused)"

      assert %{state: :failed, reason: :key_refused} = reply_of(context, conversation)
      assert ScriptedModel.requests() == []
    end

    test "is cut by the limit of an answer: the words stay, with the reason", context do
      ScriptedModel.script([{:cut, "Biscuit is a"}])
      {conversation, _message} = ask!(context)
      work!()

      assert %{state: :complete, reason: :cut, text: "Biscuit is a"} =
               reply_of(context, conversation)
    end

    test "stops at the limit of steps when the model asks for tools without end", context do
      ScriptedModel.script(List.duplicate({:tool, "find_residents", %{}}, 8))
      {conversation, _message} = ask!(context)

      capture_log(fn -> work!() end)

      assert %{state: :failed, reason: :too_many_steps} = reply = reply_of(context, conversation)
      # Each of the eight requests is billed, and counted.
      assert length(ScriptedModel.requests()) == 8
      assert Ash.load!(reply, [], authorize?: false).usage["output"] == 8 * 50
    end

    test "fails when the library gives an error before the stream", context do
      ScriptedModel.script([{:error, :timeout}])
      {conversation, _message} = ask!(context)

      log = capture_log(fn -> work!() end)
      assert log =~ "[warning] Ruby: a reply failed (provider_down)"

      assert %{state: :failed, reason: :provider_down} = reply_of(context, conversation)
    end

    # The fake server of the tests below cannot answer 529: Plug has no
    # such status. So the error of the library comes from the script, as
    # the library raises it out of a stream.
    test "fails as a busy provider when the provider is overloaded (529)", context do
      overloaded =
        ReqLLM.Error.API.Stream.exception(
          reason: "HTTP 529",
          cause: ReqLLM.Error.API.Request.exception(reason: "Overloaded", status: 529)
        )

      ScriptedModel.script([{:raise, overloaded}])
      {conversation, _message} = ask!(context, "Who is #{@marker}?")

      log = capture_log(fn -> assert %{success: 1} = work!() end)
      assert log =~ "[warning] Ruby: a reply failed (provider_busy)"
      refute log =~ @marker

      assert %{state: :failed, reason: :provider_busy, text: ""} = reply_of(context, conversation)
    end

    test "after a fault of Rescord is failed, and the job keeps no word of the fault", context do
      # A fault in the middle of the loop, with words of its own.
      ScriptedModel.script([{:raise, "the model fell over with a plum"}])
      {conversation, _message} = ask!(context, "Who is #{@marker}?")

      log = capture_log(fn -> assert %{discard: 1} = Oban.drain_queue(queue: :ruby) end)

      assert %{state: :failed, reason: :unknown} = reply_of(context, conversation)

      # The error of the job has the shape of the fault, and none of its words.
      assert [%{state: "discarded", errors: [%{"error" => error}]}] = jobs()
      assert error =~ "Ruby could not write a reply: RuntimeError"
      refute error =~ "plum"
      refute error =~ @marker
      refute log =~ "plum"
      refute log =~ @marker

      # The conversation is free again.
      ScriptedModel.script([{:text, "Yes."}])
      assert {:ok, _message} = Ruby.say(conversation.id, "Again?", context.as_ana)
    end

    test "of a conversation that its member removed writes nothing", context do
      ScriptedModel.script([])
      {conversation, message} = ask!(context)
      :ok = Ruby.remove_conversation(conversation, context.as_ana)

      work!()

      assert Ash.read!(Message, tenant: context.organisation, authorize?: false) == []
      assert ScriptedModel.requests() == []

      # A write of a reply whose conversation went while it was written.
      assert Replies.stop_asked?(message, context.organisation)
      assert Replies.save(%{message | source: :ruby}, "words", [], context.organisation) == :gone
    end
  end

  describe "against a server that plays the provider" do
    # The fake provider fails on purpose, and ReqLLM logs each failure.
    @describetag capture_log: true

    setup do
      # The first use of the catalogue of ReqLLM takes some seconds.
      ReqLLM.model!("anthropic:claude-opus-5-5")
      :ok
    end

    defp fake!(steps) do
      {:ok, fake} = FakeAnthropic.start_link(steps)
      FakeAnthropic.via(fake)
      fake
    end

    test "the request has the prompt in the cache, the tools and the header", context do
      fake = fake!([{:text, "Biscuit is in your care."}])
      {conversation, message} = ask!(context)
      work!()

      assert %{state: :complete, reason: nil, text: "Biscuit is in your care."} =
               reply = reply_of(context, conversation)

      # What the fake reported: 12 new tokens, 5,000 from the cache, 300 to
      # the cache and 40 of answer, at the prices of Opus.
      reply = Ash.load!(reply, [], authorize?: false)

      assert reply.usage == %{
               "input" => 12,
               "cache_read" => 5_000,
               "cache_write" => 300,
               "output" => 40
             }

      assert reply.cost_microdollars == 48 + 1_000 + 2_400 + 800

      assert [%{body: body, headers: headers}] = FakeAnthropic.requests(fake)
      assert body["model"] == "claude-opus-5-5"
      assert body["max_tokens"] == 4_096
      assert body["stream"] == true

      system = Prompt.system()

      assert [%{"text" => ^system, "cache_control" => %{"type" => "ephemeral", "ttl" => "1h"}}] =
               body["system"]

      assert Enum.map(body["tools"], & &1["name"]) ==
               ["find_residents", "get_task", "tasks_for_day"]

      assert Jason.encode!(body["messages"]) =~ "rescue: Wattle Creek"
      assert Jason.encode!(body["messages"]) =~ "Who is in our care?"
      assert headers["x-api-key"] == key()
      refute Jason.encode!(body) =~ key()
      refute Jason.encode!(body) =~ to_string(context.ana.email)
      assert message.header =~ "rescue: Wattle Creek"
    end

    for {status, words, reason, level} <- [
          {500, "Internal server error", :provider_down, "warning"},
          {401, "invalid x-api-key", :key_refused, "error"},
          {403, "forbidden", :key_refused, "error"},
          {400, "You have reached your specified API usage limits.", :provider_limit, "error"},
          {400, "messages: bad", :request_refused, "error"}
        ] do
      test "the provider answers #{status} (#{reason}): the reply fails with that reason",
           context do
        body = %{type: "error", error: %{type: "an_error", message: unquote(words)}}
        fake!(List.duplicate({:status, unquote(status), body}, 4))

        {conversation, _message} = ask!(context, "Who is #{@marker}?")
        log = capture_log(fn -> work!() end)

        assert %{state: :failed, reason: unquote(reason), text: ""} =
                 reply = reply_of(context, conversation)

        assert Ash.load!(reply, [], authorize?: false).cost_microdollars == 0

        # The line says the reason. No line holds a word of the question.
        assert log =~ "[#{unquote(level)}] Ruby: a reply failed (#{unquote(reason)})"
        refute log =~ @marker
      end
    end

    test "the provider is busy for a moment (429)", context do
      body = %{type: "error", error: %{type: "rate_limit_error", message: "Too fast"}}
      fake!(List.duplicate({:status, 429, body}, 6))

      {conversation, _message} = ask!(context, "Who is #{@marker}?")
      log = capture_log(fn -> work!() end)

      assert %{state: :failed, reason: :provider_busy} = reply_of(context, conversation)
      refute log =~ @marker
    end

    test "nothing listens at the address", context do
      fake!([])
      Application.put_env(:rescord, :fake_anthropic_url, "http://127.0.0.1:1")

      {conversation, _message} = ask!(context, "Who is #{@marker}?")
      log = capture_log(fn -> work!() end)

      assert %{state: :failed, reason: :provider_down} = reply_of(context, conversation)
      assert log =~ "Ruby: a reply failed (provider_down)"
      refute log =~ @marker
    end

    test "the connection breaks in the middle: the words that arrived stay", context do
      fake!([{:break, "Biscuit is a guinea pig and"}])

      {conversation, _message} = ask!(context, "Who is #{@marker}?")
      log = capture_log(fn -> work!() end)

      assert %{state: :failed, reason: :provider_down, text: "Biscuit is a guinea pig and"} =
               reply = reply_of(context, conversation)

      # The tokens of the prompt are known. The tokens of the answer are a
      # count of the bytes that arrived, three for a token.
      assert %{"input" => 12, "cache_read" => 5_000, "cache_write" => 300, "output" => 9} =
               Ash.load!(reply, [], authorize?: false).usage

      refute log =~ @marker
    end

    test "the provider refuses to answer: a failed reply with its reason, and it is billed",
         context do
      fake!([{:refusal, "I can't help with that."}])
      {conversation, _message} = ask!(context)
      work!()

      assert %{state: :failed, reason: :refused} = reply = reply_of(context, conversation)
      assert Ash.load!(reply, [], authorize?: false).cost_microdollars > 0
    end

    test "the member removes the conversation while Ruby answers: the job ends, and no row stays",
         context do
      fake!([{:slow, "one two three four five six seven eight nine ten", 300}])
      {conversation, _message} = ask!(context)
      as_ana = context.as_ana

      remove =
        Task.async(fn ->
          Process.sleep(400)
          Ruby.remove_conversation!(conversation, as_ana)
        end)

      work!()
      Task.await(remove)

      assert Ash.read!(Message, tenant: context.organisation, authorize?: false) == []
      assert [%{state: state}] = jobs()
      assert state in ["completed", "cancelled"]
    end

    test "the member stops the answer: the request ends, and the words so far stay", context do
      whole = "one two three four five six seven eight nine ten"
      fake = fake!([{:slow, whole, 300}])
      {conversation, message} = ask!(context)

      # The member presses Stop while the job reads the stream.
      as_ana = context.as_ana

      stop =
        Task.async(fn ->
          Process.sleep(400)
          Ruby.stop_reply!(message, as_ana)
        end)

      work!()
      Task.await(stop)

      assert %{state: :stopped, reason: nil, text: text} = reply = reply_of(context, conversation)
      assert text != ""
      assert text != whole
      assert String.starts_with?(whole, text)

      # The provider said the tokens of the prompt at the start. The tokens
      # of the answer are a count of the words that arrived.
      reply = Ash.load!(reply, [], authorize?: false)
      assert %{"input" => 12, "cache_read" => 5_000, "output" => output} = reply.usage
      assert output == div(byte_size(text) + 2, 3)
      assert reply.cost_microdollars > 0
      assert [_one_request] = FakeAnthropic.requests(fake)

      # A reply that the member stopped is billed, and counted.
      assert [%{replies: 1, stopped: 1, output_tokens: ^output} = row] =
               Ash.read!(Rescord.Ruby.Usage, tenant: context.organisation, authorize?: false)

      assert row.cost_microdollars == reply.cost_microdollars
    end
  end
end
