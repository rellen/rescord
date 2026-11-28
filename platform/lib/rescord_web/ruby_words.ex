defmodule RescordWeb.RubyWords do
  @moduledoc """
  The words of the assistant, Ruby (ADR 0069): the services of a provider,
  its key as a page may say it, what a test found, the amounts of money of
  its form, and where Ruby stands for an organisation.

  A page of a root user has no organisation and so no time zone: a day and
  a time here are in UTC, and a time says so.
  """

  @services [
    anthropic: "Anthropic",
    bedrock: "Amazon Bedrock",
    ollama: "Ollama",
    openai_compatible: "An OpenAI-compatible service"
  ]

  @efforts [low: "Low", medium: "Medium", high: "High"]

  @doc "The services of a provider, each with its words, in order."
  def services, do: @services

  @doc "The words of a service."
  def service(kind), do: Keyword.fetch!(@services, kind)

  @doc "The service with the text of a path or of a field, or `:error`. It makes no atom."
  def service_of(text) when is_binary(text) do
    case Enum.find(@services, fn {kind, _words} -> Atom.to_string(kind) == text end) do
      {kind, _words} -> {:ok, kind}
      nil -> :error
    end
  end

  def service_of(_other), do: :error

  @doc "What each service is, in a sentence for the person who chooses."
  def about(:anthropic),
    do: "Claude, at Anthropic. The records of a question go to Anthropic."

  def about(:bedrock),
    do: "Claude, at Amazon Web Services, in the region that you name."

  def about(:ollama),
    do:
      "A model on a machine of your own. With this service Ruby only reads: it cannot offer to add or change a record."

  def about(:openai_compatible),
    do:
      "A server that speaks the chat API of OpenAI, such as llama.cpp or vLLM. " <>
        "With this service Ruby only reads: it cannot offer to add or change a record."

  @doc "The efforts, as the options of a select."
  def efforts, do: for({effort, words} <- @efforts, do: {words, Atom.to_string(effort)})

  @doc "A day, such as 3 March 2026, in UTC."
  def day(%DateTime{} = instant), do: Calendar.strftime(instant, "%-d %B %Y")

  @doc "A day and a time, such as 28 November 2026 at 09:14 UTC."
  def time(%DateTime{} = instant), do: Calendar.strftime(instant, "%-d %B %Y at %H:%M UTC")

  @doc "The key of a provider, as the list says it. It is never the key."
  def key(%{kind: :ollama}), do: "Takes no key"
  def key(%{key_set_at: nil}), do: "No key"
  def key(%{key_hint: nil, key_set_at: set_at}), do: "Set on #{day(set_at)}"
  def key(%{key_hint: hint, key_set_at: set_at}), do: "Ends in #{hint}, set on #{day(set_at)}"

  @doc """
  The words below the key field. `provider` is `nil` for a new provider.
  `retype?` says that the person typed a key that the page did not keep.
  """
  def key_hint(provider, kind, retype?) do
    stored =
      case provider do
        nil ->
          "Rescord keeps the key encrypted, and no page shows it again."

        %{key_set_at: nil} ->
          "This provider has no key. Rescord keeps a key encrypted, and no page shows it again."

        %{key_hint: nil, key_set_at: set_at} ->
          "The key was set on #{day(set_at)}. Leave the field empty to keep it. " <>
            "A new key takes its place: then revoke the old one at the service."

        %{key_hint: hint, key_set_at: set_at} ->
          "The key ends in #{hint} and was set on #{day(set_at)}. Leave the field empty to keep it. " <>
            "A new key takes its place: then revoke the old one at the service."
      end

    optional =
      if kind == :openai_compatible and (provider == nil or provider.key_set_at == nil),
        do: " Leave the field empty for a server that asks for no key.",
        else: ""

    again = if retype?, do: " Type it again: Rescord did not keep what you typed.", else: ""

    stored <> optional <> again
  end

  @doc "What the last test of a provider found: the kind of the state, and a word."
  def test_state(%{tested_at: nil}), do: {"none", "Not tested"}
  def test_state(%{test_result: :ok}), do: {"ok", "Answered"}
  def test_state(_failed), do: {"alert", "Failed"}

  @doc """
  Why a test failed, and what to do, for the root user. Each reason of
  `Rescord.Ruby.Reason` has a sentence.
  """
  def failure(:key_refused),
    do:
      "the service refused the key, or Rescord could not open the key that it keeps. " <>
        "Type the key again below, or make a new one at the service."

  def failure(:provider_down),
    do: "the service did not answer. Check the address, and the network of this server."

  def failure(:provider_busy), do: "the service is busy. Try again in a minute."

  def failure(:provider_limit),
    do: "the account is at the spend limit that its owner set at the service."

  def failure(:request_refused),
    do: "the service refused the request. Check the name of the model."

  def failure(:refused), do: "the model refused to answer the test."
  def failure(:cut), do: "the answer of the test was cut short."
  def failure(:too_many_steps), do: "the test took too many steps."
  def failure(:allowance), do: "the allowance of the month is used."
  def failure(:member_allowance), do: "the share of one member for the month is used."
  def failure(:rate), do: "there were too many requests. Wait a moment."
  def failure(:too_long), do: "the request was too long for the model."

  def failure(:unknown),
    do: "something went wrong that Rescord cannot name. Try again, and then check each field."

  @doc """
  Where Ruby stands for an organisation (`Rescord.Ruby.status/1`), in a
  few words for the settings page.
  """
  def state(:not_set_up), do: "Not set up on this server"
  def state(:off), do: "Off"
  def state(:on), do: "On"
  def state({:stopped, :place}), do: "Off: the place of the records changed"
  def state({:stopped, :provider}), do: "Off: this server took its service away"

  @doc "Where Ruby stands for an organisation, as a sentence below the title of its page."
  def standing(:not_set_up), do: "It is not set up on this server."
  def standing(:off), do: "It is off until a person who can change the settings turns it on."
  def standing(:on), do: "It is on."

  def standing({:stopped, _why}),
    do: "It is off until a person who can change the settings agrees to where the records go."

  @doc """
  Why Ruby stopped for the organisation with this name, and what to do,
  for a person who can change the settings. `others?` says whether the
  server offers a service that the person can choose.
  """
  def stopped(:place, name, _others?),
    do:
      "Ruby is off for #{name}: the person who runs this server changed where the records go. " <>
        "Read the new place. Ruby answers again when you agree."

  def stopped(:provider, name, true),
    do:
      "Ruby is off for #{name}: this server does not offer the service that #{name} agreed to " <>
        "any more. Read the place below. Ruby answers again when you turn it on."

  def stopped(:provider, name, false),
    do:
      "Ruby is off for #{name}: this server does not offer the service that #{name} agreed to " <>
        "any more, and it offers no other one. The person who runs the server can offer one."

  @doc "How many organisations have Ruby on with a provider, for the page of a root user."
  def organisations(0), do: "No organisation has Ruby on with this provider."
  def organisations(1), do: "1 organisation has Ruby on with this provider."
  def organisations(count), do: "#{count} organisations have Ruby on with this provider."

  @doc "Whole US cents as US dollars, for a field: `2000` is `20`, and `1250` is `12.50`."
  def dollars(nil), do: ""
  def dollars(cents) when is_integer(cents) and rem(cents, 100) == 0, do: "#{div(cents, 100)}"

  def dollars(cents) when is_integer(cents),
    do:
      "#{div(cents, 100)}.#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"

  # Millionths of a US dollar in one cent.
  @cent 10_000

  @doc "Millionths of a US dollar as whole US cents, to the nearest cent."
  def cents_of(microdollars) when is_integer(microdollars), do: div(microdollars + 5_000, 10_000)

  @doc """
  What went of the allowance of a month, for the label of its `<meter>`:
  "About 12.40 of 20 US dollars used". The use is a sum of prices that
  Rescord works out, and the bill of the provider can differ a little, so
  it says "about".
  """
  def used(microdollars, allowance) when is_integer(microdollars) and is_integer(allowance),
    do: "About #{amount(cents_of(microdollars))} of #{dollars(allowance)} US dollars used"

  @doc "The share of the allowance that went, in whole percent, rounded down: \"62%\"."
  def share(microdollars, allowance) when is_integer(allowance) and allowance > 0,
    do: "#{div(microdollars * 100, allowance * @cent)}%"

  @doc """
  What the use of the month says from 80% of the allowance on, or `nil`
  below it. It compares the millionths of a dollar, as
  `Rescord.Ruby.Allowance.room?/2` does, so the page says "used" exactly
  when `say` refuses. An allowance of nothing answers nobody.
  """
  def use_warning(microdollars, allowance, %Date{} = month)
      when is_integer(microdollars) and is_integer(allowance) and allowance > 0 do
    words = RescordWeb.Locale.month(month)

    cond do
      microdollars >= allowance * @cent ->
        "The allowance of #{words} is used: Ruby answers nobody until the next month, " <>
          "or until you raise the allowance in the form above."

      microdollars * 5 >= allowance * 4 * @cent ->
        "80% or more of the allowance of #{words} is used. When it is all used, " <>
          "Ruby answers nobody until the next month."

      true ->
        nil
    end
  end

  def use_warning(_microdollars, 0, _month),
    do:
      "The allowance is 0 US dollars: Ruby answers nobody until you raise the allowance " <>
        "in the form above."

  def use_warning(_microdollars, _allowance, _month), do: nil

  @doc "A cost of the use, in US dollars with the word \"about\": \"about 6.10\"."
  def about_dollars(microdollars) when is_integer(microdollars),
    do: "about #{amount(cents_of(microdollars))}"

  # Whole cents with two places, as a use reads: "3.00" and "12.40".
  defp amount(cents) when rem(cents, 100) == 0, do: dollars(cents) <> ".00"
  defp amount(cents), do: dollars(cents)

  @doc """
  Millionths of a US dollar as US dollars, for a field: the price of a
  million tokens `4000000` is `4`, and `100000` is `0.1`.
  """
  def price(nil), do: ""

  def price(millionths) when is_integer(millionths) do
    millionths
    |> Decimal.new()
    |> Decimal.div(1_000_000)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  @doc "The whole US cents of an amount of US dollars that a person typed, or `:error`."
  def cents(text), do: scaled(text, 100)

  @doc "The millionths of a US dollar of an amount that a person typed, or `:error`."
  def millionths(text), do: scaled(text, 1_000_000)

  # The things to ask on the start of a conversation, each with the tool
  # that answers it: the page offers a thing only to a person who gets
  # that tool (`Rescord.Ruby.reads?/3`).
  @asks [
    {"tasks_for_day", "What is still to do today?"},
    {"care_overview", "Who is on medication today?"},
    {"stock_levels", "What is running low?"},
    {"overdue_tasks", "Which tasks are late?"},
    {"care_overview", "Who has not been weighed this month?"}
  ]

  @doc "The things to ask, each as `{tool, words}`, in the order of the start page."
  def asks, do: @asks

  @doc """
  The things to ask about a record, for a conversation that is about it
  (`Rescord.Ruby.about/2`), each with the tool that answers it, so that a
  page offers only what the role can read.
  """
  def asks_about(%{kind: "resident"} = about) do
    name = about.name || "this resident"

    [
      {"resident_timeline", "What happened to #{name} this week?"},
      {"resident_timeline", "When was #{name} last weighed?"},
      {"resident_profile", "What does the record of #{name} say?"},
      {"housing", "Where does #{name} live?"}
    ]
  end

  def asks_about(%{kind: "group"} = about) do
    name = about.name || "this group"

    [
      {"find_residents", "Who is in #{name}?"},
      {"housing", "Where does #{name} live?"}
    ]
  end

  def asks_about(%{kind: "location"} = about) do
    name = about.name || "this place"

    [
      {"housing", "Who lives in #{name}?"},
      {"housing", "How full is #{name}?"}
    ]
  end

  def asks_about(%{kind: "item"} = about) do
    name = about.name || "this item"

    [
      {"stock_levels", "How much #{name} is left?"},
      {"stock_levels", "Is #{name} running low?"}
    ]
  end

  @doc """
  When a message was written, in the time zone of the organisation: the
  time alone for today, and the date and the time before.
  """
  def moment(%DateTime{} = instant, organisation) do
    local = Rescord.Accounts.local_time(organisation, instant)

    if Rescord.Accounts.local_date(organisation, instant) == Rescord.Accounts.today(organisation),
      do: RescordWeb.Locale.time(local),
      else: RescordWeb.Locale.date_time(local)
  end

  @doc "The title of a conversation, also before Ruby gave it one."
  def title(%{title: title}) when is_binary(title) and title != "", do: title
  def title(_conversation), do: "A new conversation"

  @doc """
  The small line of a conversation in a list: the time of its last
  message, the record that it is about, when the person can read it, and
  how many messages it holds. "14:02 · about Biscuit · 4 messages".
  """
  def conversation_line(conversation, about, organisation) do
    [
      moment(conversation.last_message_at, organisation),
      about && "about " <> (about.name || "a record with no name"),
      is_integer(conversation.message_count) &&
        RescordWeb.Locale.count(conversation.message_count, "message", "messages")
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" · ")
  end

  @doc "A number of days: \"1 day\", \"90 days\"."
  def days(count) when is_integer(count), do: RescordWeb.Locale.count(count, "day", "days")

  @doc """
  What the one `role="status"` of the page of a conversation says once,
  for a state of the answer.
  """
  def said(:working), do: "Ruby is working."
  def said(:writing), do: "Ruby is writing the answer."
  def said(:complete), do: "Ruby answered."
  def said(:awaiting), do: "Ruby waits for you."
  def said(:stopped), do: "You stopped the answer."
  def said(:failed), do: "Ruby could not answer."
  def said(_other), do: nil

  # What each tool does, while it runs and when it ran, and what it counts.
  # A tool with no line here shows as "Reads the records", and never as its
  # name: `RubyWordsTest` holds this list to the catalogue.
  @steps %{
    "find_residents" =>
      {"Looks for residents", "Looked for residents", {"resident", "residents"}},
    "get_task" => {"Reads a task", "Read a task", {"task", "tasks"}},
    "tasks_for_day" =>
      {"Looks at the tasks of a day", "Looked at the tasks of a day", {"task", "tasks"}},
    "overdue_tasks" =>
      {"Looks at the tasks that are late", "Looked at the tasks that are late", {"task", "tasks"}},
    "resident_profile" =>
      {"Reads the profile of a resident", "Read the profile of a resident",
       {"resident", "residents"}},
    "resident_timeline" =>
      {"Reads the journal of a resident", "Read the journal of a resident", {"entry", "entries"}},
    "housing" => {"Looks at who lives where", "Looked at who lives where", {"place", "places"}},
    "find_locations" => {"Looks for places", "Looked for places", {"place", "places"}},
    "stock_levels" => {"Looks at the stock", "Looked at the stock", {"item", "items"}},
    "find_items" =>
      {"Looks for items of the inventory", "Looked for items of the inventory", {"item", "items"}},
    "care_overview" =>
      {"Looks at the care of the residents", "Looked at the care of the residents",
       {"resident", "residents"}}
  }

  @doc "The names of the tools that have words for their steps."
  def step_tools, do: Map.keys(@steps)

  @doc """
  The line of a step of Ruby: what the tool does while it runs, and what
  it did when it ended. From the name of the tool and its arguments, as
  `Rescord.Ruby.Steps` keeps them, and never from the words of the model.
  """
  def step(%{"tool" => "care_overview", "arguments" => %{"question" => "on_medication"}} = step),
    do: tense(step, "Looks at who is on medication", "Looked at who is on medication")

  def step(
        %{"tool" => "care_overview", "arguments" => %{"question" => "no_weight_since"}} = step
      ),
      do: tense(step, "Looks at who has not been weighed", "Looked at who has not been weighed")

  def step(%{"tool" => "tasks_for_day", "arguments" => %{"date" => date}} = step)
      when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, day} ->
        day = RescordWeb.TaskWords.day(day)
        tense(step, "Looks at the tasks of #{day}", "Looked at the tasks of #{day}")

      {:error, _not_a_date} ->
        step(Map.delete(step, "arguments"))
    end
  end

  def step(%{"tool" => tool} = step) do
    case Map.fetch(@steps, tool) do
      {:ok, {running, ran, _noun}} -> tense(step, running, ran)
      :error -> tense(step, "Reads the records", "Read the records")
    end
  end

  defp tense(%{"state" => state}, _running, ran) when state in ["done", "failed"], do: ran
  defp tense(_step, running, _ran), do: running

  @doc "What a step found, such as \"19 tasks\", or why it found nothing. `nil` while it runs."
  def outcome(%{"state" => "failed"}), do: "Ruby could not read this"
  def outcome(%{"state" => "stopped"}), do: "You stopped the answer here"

  def outcome(%{"state" => "done", "tool" => tool, "count" => count}) when is_integer(count) do
    {one, many} =
      case Map.fetch(@steps, tool) do
        {:ok, {_running, _ran, noun}} -> noun
        :error -> {"record", "records"}
      end

    if count == 1, do: "1 #{one}", else: "#{count} #{many}"
  end

  def outcome(_step), do: nil

  @doc "The one line of the status of the page while a step runs: \"Ruby looks at the stock.\""
  def said_step(%{"state" => "running"} = step) do
    {first, rest} = step |> step() |> String.split_at(1)
    "Ruby #{String.downcase(first)}#{rest}."
  end

  def said_step(_step), do: nil

  @doc "The summary of the steps of a reply: \"What Ruby read: 3 steps\"."
  def steps_summary([_one]), do: "What Ruby read: 1 step"
  def steps_summary(steps), do: "What Ruby read: #{length(steps)} steps"

  @doc """
  What went wrong with a reply, or with a message that Ruby refused, for
  the member, in the place of the answer: one sentence for each reason of
  `Rescord.Ruby.Reason`, and no other. "Nothing was recorded" is in each
  one where it is true, since it is the first thing that a member asks.

  The allowance is of a month of UTC (`Rescord.Ruby.Allowance`), so the
  option `today` is a day of UTC. The option `allowance` is the allowance
  of the organisation, in cents, when the page knows it: an allowance of
  nothing never comes back with a new month.
  """
  def problem(reason, organisation, opts \\ [])

  def problem(reason, _organisation, _opts) when reason in [:provider_down, :unknown],
    do:
      "Ruby could not answer: the service that Ruby thinks with did not respond. " <>
        "Nothing was recorded. The pages of Rescord work as before."

  def problem(:request_refused, _organisation, _opts),
    do:
      "Ruby could not answer: the service that Ruby thinks with refused the request. " <>
        "Nothing was recorded. The pages of Rescord work as before."

  def problem(:provider_busy, _organisation, _opts),
    do: "Ruby is busy. Nothing was recorded. Try again in a minute."

  def problem(:rate, _organisation, _opts), do: "Wait a moment before you ask again."

  def problem(:allowance, %{name: name}, opts) do
    today = Keyword.get(opts, :today, Date.utc_today())

    case Keyword.fetch(opts, :allowance) do
      {:ok, cents} when cents in [nil, 0] ->
        "Ruby has no allowance for #{name}. It answers when an administrator " <>
          "sets one in the settings."

      _some ->
        month_used(name, today)
    end
  end

  def problem(:member_allowance, _organisation, opts) do
    today = Keyword.get(opts, :today, Date.utc_today())
    next = today |> Date.end_of_month() |> Date.add(1) |> RescordWeb.Locale.date()

    "You have used your share of Ruby for this month. It starts again on #{next}."
  end

  def problem(:provider_limit, _organisation, _opts),
    do:
      "Ruby has reached the limit of this server for the month. Nothing was recorded. " <>
        "The pages of Rescord work as before."

  def problem(:key_refused, _organisation, _opts),
    do: "Ruby is not set up on this server. Tell the person who runs it. Nothing was recorded."

  def problem(:refused, _organisation, _opts),
    do: "Ruby cannot help with that. Nothing was recorded."

  def problem(:cut, _organisation, _opts), do: "The answer was cut short. Ask for the rest."

  def problem(:too_many_steps, _organisation, _opts),
    do: "Ruby stopped: the question took too many steps. Ask for a smaller part."

  def problem(:too_long, _organisation, _opts),
    do: "This conversation is long. Start a new one, and Ruby reads the records again."

  defp month_used(name, today) do
    month = today |> Date.beginning_of_month() |> RescordWeb.Locale.month()
    next = today |> Date.end_of_month() |> Date.add(1) |> RescordWeb.Locale.date()

    "Ruby has used the allowance of #{name} for #{month}. It answers again on #{next}, " <>
      "or when an administrator changes the allowance in the settings."
  end

  @doc """
  The way on after a problem, for its reason:

    * `:again` - "Try again" sends the message of the member again: a
      second try can go better;
    * `:rest` - "Ask for the rest";
    * `:new` - "New conversation": this one fails again. A refusal has
      none here: the conversation is closed, and the form says so;
    * `:settings` - for a person who can change the settings of Ruby, a
      link to them;
    * `nil` - the field, or nothing that the member can do.
  """
  def way_on(reason) when reason in [:provider_down, :unknown, :provider_busy, :rate], do: :again
  def way_on(:cut), do: :rest
  def way_on(reason) when reason in [:request_refused, :too_long], do: :new
  def way_on(reason) when reason in [:allowance, :member_allowance], do: :settings
  def way_on(_reason), do: nil

  @doc "Whether a second try of the same message can go better (\"Try again\")."
  def again?(reason), do: way_on(reason) == :again

  @doc "The words that \"Ask for the rest\" sends."
  def rest, do: "Please go on with the rest of the answer."

  @doc "Whether the words of a reply that ended for this reason stay on the page."
  def keeps_words?(:refused), do: false
  def keeps_words?(_reason), do: true

  # An amount with more digits than the unit holds is refused, and not
  # rounded: the person sees what Rescord keeps.
  defp scaled(text, unit) when is_binary(text) do
    with {%Decimal{coef: digits} = amount, ""} when is_integer(digits) <-
           Decimal.parse(String.trim(text)),
         false <- Decimal.negative?(amount),
         scaled = Decimal.mult(amount, unit),
         true <- Decimal.integer?(scaled),
         true <- Decimal.compare(scaled, 1_000_000_000) != :gt do
      {:ok, Decimal.to_integer(scaled)}
    else
      _other -> :error
    end
  end

  defp scaled(_other, _unit), do: :error
end
