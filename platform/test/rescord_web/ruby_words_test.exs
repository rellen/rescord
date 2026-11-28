defmodule RescordWeb.RubyWordsTest do
  @moduledoc """
  Holds the words of the assistant to the fixed lists (ADR 0069): each
  service of a provider, each effort and each reason of a failure has
  words, and the words name no value that a list does not have. It holds
  also the amounts of money of the form of a provider, and the words of
  where Ruby stands for an organisation.
  """

  use ExUnit.Case, async: true

  alias Rescord.Ruby.Provider
  alias Rescord.Ruby.Reason
  alias RescordWeb.RubyWords

  defp values(attribute),
    do: Ash.Resource.Info.attribute(Provider, attribute).constraints[:one_of]

  test "each service has words, and a path names no other service" do
    kinds = Keyword.keys(RubyWords.services())
    assert Enum.sort(kinds) == Enum.sort(values(:kind))

    for kind <- kinds do
      refute RubyWords.service(kind) =~ "_"
      assert RubyWords.about(kind) =~ ~r/\.$/
      assert RubyWords.service_of(Atom.to_string(kind)) == {:ok, kind}
    end

    assert RubyWords.service_of("no_such_service") == :error
    assert RubyWords.service_of(nil) == :error
  end

  test "each effort has a word" do
    efforts = for {_words, value} <- RubyWords.efforts(), do: value
    assert Enum.sort(efforts) == values(:effort) |> Enum.map(&Atom.to_string/1) |> Enum.sort()
    for {words, _value} <- RubyWords.efforts(), do: refute(words =~ "_")
  end

  test "each reason of a failure has a sentence" do
    for reason <- Reason.all() do
      sentence = RubyWords.failure(reason)
      assert sentence =~ ~r/\.$/, "the sentence of #{reason} ends with a full stop"
      refute sentence =~ "_"
    end

    # The result of a test is `:ok` or a reason, and nothing else.
    assert Enum.sort(values(:test_result)) == Enum.sort([:ok | Reason.all()])
  end

  test "the state of the last test is a kind and a word" do
    assert RubyWords.test_state(%{tested_at: nil, test_result: nil}) == {"none", "Not tested"}
    now = DateTime.utc_now()
    assert RubyWords.test_state(%{tested_at: now, test_result: :ok}) == {"ok", "Answered"}

    for reason <- Reason.all() do
      assert RubyWords.test_state(%{tested_at: now, test_result: reason}) == {"alert", "Failed"}
    end
  end

  test "the words of a key never hold more than its hint" do
    set_at = ~U[2026-03-03 09:14:00.000000Z]

    assert RubyWords.key(%{kind: :ollama, key_set_at: nil, key_hint: nil}) == "Takes no key"
    assert RubyWords.key(%{kind: :anthropic, key_set_at: nil, key_hint: nil}) == "No key"

    assert RubyWords.key(%{kind: :anthropic, key_set_at: set_at, key_hint: nil}) ==
             "Set on 3 March 2026"

    assert RubyWords.key(%{kind: :anthropic, key_set_at: set_at, key_hint: "wxyz"}) ==
             "Ends in wxyz, set on 3 March 2026"

    assert RubyWords.time(set_at) == "3 March 2026 at 09:14 UTC"
  end

  test "the hint of the key field says to type the key again only after a refusal" do
    refute RubyWords.key_hint(nil, :anthropic, false) =~ "Type it again"
    assert RubyWords.key_hint(nil, :anthropic, true) =~ "Type it again"

    assert RubyWords.key_hint(nil, :openai_compatible, false) =~ "asks for no key"
    refute RubyWords.key_hint(nil, :anthropic, false) =~ "asks for no key"

    kept = %{key_set_at: ~U[2026-03-03 09:14:00.000000Z], key_hint: "wxyz"}
    assert RubyWords.key_hint(kept, :anthropic, false) =~ "ends in wxyz"
    refute RubyWords.key_hint(kept, :openai_compatible, false) =~ "asks for no key"
  end

  test "each place where Ruby stands for an organisation has words" do
    statuses = [:not_set_up, :off, :on, {:stopped, :place}, {:stopped, :provider}]

    for status <- statuses do
      refute RubyWords.state(status) =~ "_"
      assert RubyWords.standing(status) =~ ~r/^It is .+\.$/
    end

    # Only one of them says that Ruby is on.
    assert Enum.filter(statuses, &(RubyWords.state(&1) == "On")) == [:on]
    assert Enum.filter(statuses, &(RubyWords.standing(&1) == "It is on.")) == [:on]

    for why <- [:place, :provider], others? <- [true, false] do
      sentence = RubyWords.stopped(why, "Wattle Creek", others?)
      assert sentence =~ "Ruby is off for Wattle Creek"
      assert sentence =~ ~r/\.$/
    end

    assert RubyWords.organisations(0) =~ "No organisation"
    assert RubyWords.organisations(1) =~ "1 organisation has"
    assert RubyWords.organisations(3) =~ "3 organisations have"
  end

  test "an amount in cents reads as dollars, and back" do
    assert RubyWords.dollars(nil) == ""
    assert RubyWords.dollars(2000) == "20"
    assert RubyWords.dollars(1250) == "12.50"
    assert RubyWords.dollars(5) == "0.05"

    assert RubyWords.cents("20") == {:ok, 2000}
    assert RubyWords.cents(" 12.50 ") == {:ok, 1250}
    assert RubyWords.cents("0.05") == {:ok, 5}
    assert RubyWords.cents("0") == {:ok, 0}

    for cents <- [0, 5, 99, 100, 1250, 2000, 123_456] do
      assert cents |> RubyWords.dollars() |> RubyWords.cents() == {:ok, cents}
    end
  end

  test "a price for a million tokens reads as dollars, and back" do
    assert RubyWords.price(nil) == ""
    assert RubyWords.price(4_000_000) == "4"
    assert RubyWords.price(100_000) == "0.1"
    assert RubyWords.price(0) == "0"

    assert RubyWords.millionths("4") == {:ok, 4_000_000}
    assert RubyWords.millionths("0.1") == {:ok, 100_000}

    for millionths <- [0, 1, 100_000, 4_000_000, 25_000_000] do
      assert millionths |> RubyWords.price() |> RubyWords.millionths() == {:ok, millionths}
    end
  end

  test "an amount that Rescord cannot keep exactly is refused, and not rounded" do
    assert RubyWords.cents("12.505") == :error
    assert RubyWords.millionths("0.0000001") == :error
  end

  test "what is no amount is refused" do
    for text <- ["", " ", "abc", "-1", "1e3x", "12,50", "$20", "NaN", "Infinity", "-0.01"] do
      assert RubyWords.cents(text) == :error, "#{inspect(text)} is no amount"
    end

    assert RubyWords.cents(nil) == :error
    assert RubyWords.cents(20) == :error
    # Too large for a column of a whole number of cents to be of any use.
    assert RubyWords.cents("100000000000") == :error
  end

  describe "what goes wrong, for a member" do
    @refuge %{name: "Wattle Creek"}

    test "each reason has a sentence, and a new reason fails here until it has one" do
      for reason <- Reason.all() do
        sentence = RubyWords.problem(reason, @refuge, today: ~D[2026-11-28])
        assert sentence =~ ~r/\.$/, "the sentence of #{reason} ends with a full stop"
        refute sentence =~ "_"
      end

      assert_raise FunctionClauseError, fn -> RubyWords.problem(:a_new_reason, @refuge) end
    end

    test "says that nothing was recorded where a reply failed" do
      for reason <-
            Reason.all() --
              [:rate, :allowance, :member_allowance, :cut, :too_many_steps, :too_long] do
        assert RubyWords.problem(reason, @refuge) =~ "Nothing was recorded.", "#{reason}"
      end
    end

    test "the share of a member says when it starts again (ADR 0117)" do
      assert RubyWords.problem(:member_allowance, @refuge, today: ~D[2026-11-28]) ==
               "You have used your share of Ruby for this month. It starts again on 1 December 2026."

      assert RubyWords.way_on(:member_allowance) == :settings
    end

    test "the allowance names the rescue, the month, and the day that Ruby answers again" do
      assert RubyWords.problem(:allowance, @refuge, today: ~D[2026-11-28], allowance: 2000) ==
               "Ruby has used the allowance of Wattle Creek for November 2026. " <>
                 "It answers again on 1 December 2026, or when an administrator " <>
                 "changes the allowance in the settings."

      assert RubyWords.problem(:allowance, @refuge, today: ~D[2026-12-31]) =~ "on 1 January 2027"

      # An allowance of nothing does not come back with a new month.
      for none <- [0, nil] do
        assert RubyWords.problem(:allowance, @refuge, allowance: none) ==
                 "Ruby has no allowance for Wattle Creek. It answers when an administrator " <>
                   "sets one in the settings."
      end
    end

    test "Try again only where a second try can go better" do
      assert Enum.filter(Reason.all(), &RubyWords.again?/1) ==
               [:provider_busy, :provider_down, :rate, :unknown]

      assert RubyWords.way_on(:cut) == :rest
      assert RubyWords.way_on(:too_long) == :new
      assert RubyWords.way_on(:allowance) == :settings

      for reason <- [:key_refused, :provider_limit, :too_many_steps, :refused],
          do: assert(RubyWords.way_on(reason) == nil)

      refute RubyWords.keeps_words?(:refused)
      assert RubyWords.keeps_words?(:provider_down)
      assert RubyWords.keeps_words?(nil)
    end
  end

  describe "the steps of an answer" do
    test "each tool of the catalogue has words for its step, and never its name" do
      names = for %{name: name} <- Rescord.Ruby.Catalogue.entries(), do: Atom.to_string(name)

      assert Enum.sort(names) == Enum.sort(RubyWords.step_tools())

      for name <- names, state <- ["running", "done"] do
        words = RubyWords.step(%{"tool" => name, "state" => state, "arguments" => %{}})
        refute words =~ name
        refute words =~ "_"
      end
    end

    test "a step says what it does while it runs, and what it did" do
      step = %{"tool" => "stock_levels", "arguments" => %{}, "state" => "running"}
      assert RubyWords.step(step) == "Looks at the stock"
      assert RubyWords.said_step(step) == "Ruby looks at the stock."
      assert RubyWords.outcome(step) == nil

      done = %{step | "state" => "done"} |> Map.put("count", 1)
      assert RubyWords.step(done) == "Looked at the stock"
      assert RubyWords.outcome(done) == "1 item"
      assert RubyWords.outcome(%{done | "count" => 19}) == "19 items"
      assert RubyWords.said_step(done) == nil

      assert RubyWords.outcome(%{step | "state" => "failed"}) == "Ruby could not read this"
    end

    test "a step takes its words from the arguments that code knows" do
      step = %{"tool" => "care_overview", "state" => "done"}

      assert RubyWords.step(Map.put(step, "arguments", %{"question" => "on_medication"})) ==
               "Looked at who is on medication"

      assert RubyWords.step(Map.put(step, "arguments", %{"question" => "anything"})) ==
               "Looked at the care of the residents"

      tasks = %{"tool" => "tasks_for_day", "state" => "running"}

      assert RubyWords.step(Map.put(tasks, "arguments", %{"date" => "2026-11-28"})) =~
               "Looks at the tasks of "

      assert RubyWords.step(Map.put(tasks, "arguments", %{"date" => "<b>soon</b>"})) ==
               "Looks at the tasks of a day"
    end

    test "a tool that has no words reads the records, and a count of records" do
      step = %{"tool" => "a_new_tool", "arguments" => %{}, "state" => "done", "count" => 2}
      assert RubyWords.step(step) == "Read the records"
      assert RubyWords.outcome(step) == "2 records"
    end

    test "the summary counts the steps" do
      assert RubyWords.steps_summary([%{}]) == "What Ruby read: 1 step"
      assert RubyWords.steps_summary([%{}, %{}, %{}]) == "What Ruby read: 3 steps"
    end
  end
end
