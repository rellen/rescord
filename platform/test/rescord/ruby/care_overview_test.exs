defmodule Rescord.Ruby.CareOverviewTest do
  @moduledoc """
  Holds `Rescord.Journal.care_overview/1` and the tool of the assistant
  over it, `care_overview` (ADR 0069): the residents in care on
  medication, and those with no weight for a time.

  The function reads the residents, the prescriptions and the
  measurements in a fixed number of reads, whatever the number of
  residents. The tool runs through the loop of `AshAi` with the options of
  `Rescord.Ruby.Toolbox`, as a reply runs it. The model answers from a
  script. No test calls a provider.

  The test creates an organisation, so it does not run beside others.
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ClockFixtures
  import Rescord.ResidentsFixtures
  import Rescord.RubyFixtures

  alias Rescord.{Accounts, Journal, Residents, Ruby}
  alias Rescord.Ruby.{ScriptedModel, Toolbox}
  alias Rescord.Ruby.LLM.Client

  @zone "Australia/Brisbane"

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {:ok, organisation} = Accounts.set_organisation_time_zone(organisation, @zone, actor: root)
    # The tests compare the day that a tool reads with the day of the test.
    clear_of_midnight(organisation)
    {_, administrator} = member!(organisation, :administrator, root)
    admin = [actor: administrator, tenant: organisation]
    {_, member} = member!(organisation, :member, administrator)
    options = [actor: member, tenant: organisation]
    lists = lists!(organisation, root)
    today = Accounts.today(organisation)
    {:ok, profile} = Ruby.LLM.profile_of(provider!(root))

    biscuit = resident!(lists, admin, %{name: "Biscuit"})
    clover = resident!(lists, admin, %{name: "Clover", sex: :female})
    fern = resident!(lists, admin, %{name: "Fern"})
    maple = resident!(lists, admin, %{name: "Maple"})
    gone = resident!(lists, admin, %{name: "Willow"})

    {:ok, _} =
      Residents.start_absence(%{resident_id: fern.id, reason: "At the clinic"}, admin)

    {:ok, _} =
      Residents.record_departure(
        %{resident_id: gone.id, kind: :death, departed_on: today},
        admin
      )

    now = DateTime.utc_now()

    write = fn resident, facts ->
      Journal.write_entry!(
        Map.merge(%{resident_id: resident.id, happened_at: now}, facts),
        options
      )
    end

    prescription = fn resident, medication, starts, ends ->
      write.(resident, %{
        kind: :prescription,
        medication: medication,
        dose: "0.2 mL once a day",
        route: :oral,
        starts_on: starts && Date.add(today, starts),
        ends_on: ends && Date.add(today, ends)
      })
    end

    prescription.(biscuit, "A sample antibiotic", -2, 5)
    prescription.(biscuit, "An old cream", -30, -20)
    prescription.(clover, "A cream for later", 3, 10)
    # With no first day, it runs from the day it was written.
    prescription.(fern, "A drop with no end", nil, nil)
    prescription.(gone, "A medication of one who left", -2, 5)

    measure = fn resident, kind, days_ago ->
      write.(resident, %{
        kind: :measurement,
        measure_kind_id: kind,
        value: "800",
        unit_id: lists.unit.g,
        happened_at: DateTime.add(now, -days_ago, :day)
      })
    end

    measure.(biscuit, lists.measure_kind.weight, 2)
    measure.(biscuit, lists.measure_kind.weight, 60)
    measure.(clover, lists.measure_kind.weight, 45)
    # A temperature is no weight.
    measure.(maple, lists.measure_kind.temperature, 1)

    {:ok,
     root: root,
     organisation: organisation,
     member: member,
     options: options,
     lists: lists,
     today: today,
     profile: profile,
     biscuit: biscuit,
     clover: clover,
     fern: fern,
     maple: maple}
  end

  defp call(context, user, tenant, arguments) do
    ScriptedModel.script([{:tool, "care_overview", arguments}, {:text, "Read."}])

    assert {:ok, %{final_text: "Read."}} =
             AshAi.ToolLoop.run(
               [ReqLLM.Context.user("A question")],
               Toolbox.options(user, tenant, context.profile)
             )

    Client.take_requests()

    [_question, answer] = ScriptedModel.requests()
    %{role: :tool, content: [%{type: :text, text: text}]} = List.last(answer.messages)
    text
  end

  defp call(context, arguments),
    do: call(context, context.member, context.organisation, arguments)

  defp decoded(context, arguments), do: Jason.decode!(call(context, arguments))
  defp labels(result), do: Enum.map(result["residents"], & &1["label"])

  describe "Journal.care_overview/1" do
    test "gives each resident in care, with what runs today and the newest weight", context do
      {:ok, rows} =
        Journal.care_overview(
          context.options ++ [measure_kind_ids: [context.lists.measure_kind.weight]]
        )

      assert Enum.map(rows, & &1.resident.name) == ["Biscuit", "Clover", "Fern", "Maple"]
      rows = Map.new(rows, &{&1.resident.name, &1})

      assert Enum.map(rows["Biscuit"].prescriptions, & &1.prescription.medication) ==
               ["A sample antibiotic"]

      assert rows["Clover"].prescriptions == []

      assert Enum.map(rows["Fern"].prescriptions, & &1.prescription.medication) == [
               "A drop with no end"
             ]

      # The newest of the two weights of Biscuit.
      assert DateTime.diff(DateTime.utc_now(), rows["Biscuit"].last_measured_at, :day) == 2
      assert rows["Maple"].last_measured_at == nil
    end

    test "reads a fixed number of times, whatever the number of residents", context do
      for n <- 1..5, do: resident!(context.lists, context.options, %{name: "Pip #{n}"})

      count = fn ->
        ref = make_ref()
        parent = self()

        :telemetry.attach(
          inspect(ref),
          [:rescord, :repo, :query],
          fn _event, _measure, _meta, _config -> send(parent, {ref, :query}) end,
          nil
        )

        {:ok, _rows} =
          Journal.care_overview(
            context.options ++ [measure_kind_ids: [context.lists.measure_kind.weight]]
          )

        :telemetry.detach(inspect(ref))

        Stream.repeatedly(fn -> receive do: ({^ref, :query} -> 1), after: (0 -> nil) end)
        |> Enum.take_while(& &1)
        |> length()
      end

      before = count.()
      # The event of each query of the repository: a count of none proves nothing.
      assert before > 0
      for n <- 6..15, do: resident!(context.lists, context.options, %{name: "Pip #{n}"})
      assert count.() == before
    end
  end

  describe "the tool" do
    test "gives the residents on medication today, with the words of the vet", context do
      json = call(context, %{"question" => "on_medication"})
      result = Jason.decode!(json)

      assert labels(result) == ["Biscuit", "Fern"]
      assert result["count"] == 2

      [biscuit, _fern] = result["residents"]
      assert biscuit["ref"] == "resident:" <> context.biscuit.id

      assert [%{"medication_text" => "A sample antibiotic", "dose_text" => "0.2 mL once a day"}] =
               biscuit["prescriptions"]

      refute json =~ "An old cream"
      refute json =~ "A cream for later"
      refute json =~ "Willow"
      refute json =~ context.member.id
    end

    test "gives the residents with no weight for a time, none ever first", context do
      result = decoded(context, %{"question" => "no_weight_since"})

      assert result["days"] == 30
      assert result["measure"] == ["Weight"]
      assert labels(result) == ["Fern", "Maple", "Clover"]

      clover = List.last(result["residents"])
      assert clover["days_since"] == 45
      assert hd(result["residents"])["last_measured_on"] == "never"

      # With 60 days, Clover was weighed in time.
      assert labels(decoded(context, %{"question" => "no_weight_since", "days" => 60})) ==
               ["Fern", "Maple"]
    end

    test "finds another measure kind by its name, and names the kinds when none has it",
         context do
      assert labels(decoded(context, %{"question" => "no_weight_since", "measure" => "temp"})) ==
               ["Biscuit", "Clover", "Fern"]

      assert call(context, %{"question" => "no_weight_since", "measure" => "Height"}) =~
               "no measure kind of that name. Its kinds are: Temperature, Weight"
    end

    test "answers a wrong argument in words", context do
      assert call(context, %{}) =~ "question: give one of on_medication, no_weight_since"
      assert call(context, %{"question" => "who"}) =~ "question: give one of"

      assert call(context, %{"question" => "no_weight_since", "days" => 0}) =~
               "days: give a whole number"

      assert call(context, %{"question" => "no_weight_since", "measure" => 5}) =~
               "measure: give the name of a measure kind"

      # Blank is the weight, and not each kind.
      assert decoded(context, %{"question" => "no_weight_since", "measure" => "  "})["measure"] ==
               ["Weight"]
    end

    test "gives nothing to a person who is no member, and nothing elsewhere", context do
      other = organisation!(context.root, "Banksia Rise")

      for {user, tenant} <- [
            {user!(), context.organisation},
            {context.root, context.organisation},
            {context.member, other}
          ] do
        refute call(context, user, tenant, %{"question" => "on_medication"}) =~ "Biscuit"
      end
    end
  end
end
