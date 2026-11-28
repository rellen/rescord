defmodule Rescord.Ruby.ToolsTest do
  @moduledoc """
  Holds the first tools of the assistant (ADR 0069), each through the loop
  of `AshAi` with the options of `Rescord.Ruby.Toolbox`, as a reply runs
  them: what a member gets, what a person who is no member gets, what the
  model can send, and what goes to the provider.

  The model answers from a script. No test calls a provider.

  The test creates an organisation, so it does not run beside others.
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.RubyFixtures

  alias Rescord.{Accounts, Locations, Residents, Ruby, Tasks}
  alias Rescord.Ruby.{ScriptedModel, Toolbox}
  alias Rescord.Ruby.LLM.Client

  @zone "Australia/Brisbane"

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {:ok, organisation} = Accounts.set_organisation_time_zone(organisation, @zone, actor: root)
    {_, administrator} = member!(organisation, :administrator, root)
    admin = [actor: administrator, tenant: organisation]
    {_, member} = member!(organisation, :member, administrator)

    lists = lists!(organisation, root)
    biscuit = resident!(lists, admin)
    clover = resident!(lists, admin, %{name: "Clover", sex: :female})

    {:ok, profile} = Ruby.LLM.profile_of(provider!(root))

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     admin: admin,
     member: member,
     lists: lists,
     biscuit: biscuit,
     clover: clover,
     profile: profile}
  end

  # Runs one tool call as the loop does for this person in this tenant, and
  # gives what the model reads: the text of the tool result.
  defp call(context, user, tenant, name, arguments) do
    ScriptedModel.script([{:tool, name, arguments}, {:text, "Read."}])

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

  defp call(context, name, arguments),
    do: call(context, context.member, context.organisation, name, arguments)

  defp plan!(context, title, at, values \\ %{}) do
    {:ok, due_at} = Accounts.local_instant(context.organisation, at)

    %{title: title, due_at: due_at, kind_id: context.lists.task_kind.feed}
    |> Map.merge(values)
    |> Tasks.plan_task!(context.admin)
  end

  defp names(json), do: json |> Jason.decode!() |> Map.fetch!("results") |> Enum.map(& &1["name"])

  describe "the toolbox" do
    test "gives a member the tools of the catalogue, by name", context do
      options = Toolbox.options(context.member, context.organisation, context.profile)

      assert options[:tools] == [:find_residents, :get_task]
      assert [{%ReqLLM.Tool{name: "tasks_for_day"}, run}] = options[:extra_tools]
      assert is_function(run, 2)
      assert options[:req_llm] == Client
      assert options[:max_iterations] == 8
      assert options[:tenant] == context.organisation
      # The limit of an answer and the key go with each request.
      assert options[:req_llm_opts][:max_tokens] == 4_096
      assert options[:req_llm_opts][:api_key] == key()
    end

    test "makes the actor with the level of a root user off", context do
      {_, root_member} = member!(context.organisation, :member, context.administrator)
      root_member = Ash.Seed.update!(root_member, %{root?: true})

      for user <- [context.root, root_member] do
        options = Toolbox.options(user, context.organisation, context.profile)
        assert user.root?
        refute options[:actor].root?
        assert options[:actor].id == user.id
      end
    end

    test "gives a person who is no member no digest", context do
      for user <- [context.root, user!()] do
        options = Toolbox.options(user, context.organisation, context.profile)
        assert options[:extra_tools] == []
      end
    end

    test "sends the model the three tools and the options of the profile", context do
      call(context, "find_residents", %{})
      [request | _rest] = ScriptedModel.requests()

      assert Enum.map(request.opts[:tools], & &1.name) ==
               ["find_residents", "get_task", "tasks_for_day"]

      assert %{provider: :anthropic, id: "claude-opus-5-5"} = request.model
      assert request.opts[:max_tokens] == 4_096
      assert request.opts[:reasoning_effort] == :low
    end

    test "counts each request of a turn", context do
      ScriptedModel.script([{:tool, "find_residents", %{}}, {:text, "Two residents."}])

      {:ok, result} =
        AshAi.ToolLoop.run(
          [ReqLLM.Context.user("Who is here?")],
          Toolbox.options(context.member, context.organisation, context.profile)
        )

      assert result.final_text == "Two residents."

      assert [%{finish_reason: :tool_calls}, %{finish_reason: :stop, usage: %{input: 1_000}}] =
               Client.take_requests()
    end
  end

  describe "a tool that the catalogue does not name" do
    test "does not exist for the model, and changes nothing", context do
      for name <- ["remove_resident", "plan_task", "read_settings", "providers"] do
        text = call(context, name, %{"id" => context.biscuit.id})
        assert text =~ "Unknown tool"
      end

      assert {:ok, %{}} = Residents.resident(context.biscuit.id, context.admin)
    end
  end

  describe "find_residents" do
    test "gives a member the residents, with the fields of the tool and no other", context do
      json = call(context, "find_residents", %{})

      assert %{"results" => results, "has_more" => false} = Jason.decode!(json)
      assert Enum.sort(Enum.map(results, & &1["name"])) == ["Biscuit", "Clover"]

      for resident <- results do
        assert resident |> Map.keys() |> Enum.sort() ==
                 ~w(arrived_on id name sex species_label status)

        assert resident["status"] == "in_care"
        assert resident["species_label"] == "Guinea pig"
      end

      # No id of a member, and no address.
      refute json =~ context.administrator.id
      refute json =~ to_string(context.administrator.email)
    end

    test "filters by the name whatever its case, and by the other fields of the list", context do
      assert names(
               call(context, "find_residents", %{"filter" => %{"name" => %{"ilike" => "%CLO%"}}})
             ) ==
               ["Clover"]

      assert names(call(context, "find_residents", %{"filter" => %{"sex" => %{"eq" => "male"}}})) ==
               ["Biscuit"]

      assert names(
               call(context, "find_residents", %{
                 "filter" => %{"status" => %{"eq" => "in_care"}},
                 "sort" => [%{"field" => "name", "direction" => "desc"}]
               })
             ) == ["Clover", "Biscuit"]

      assert call(context, "find_residents", %{"result_type" => "count"}) == "2"
    end

    test "refuses a filter and a sort on a field that is not of the list", context do
      for arguments <- [
            %{"filter" => %{"born_on" => %{"is_nil" => true}}},
            %{"filter" => %{"user_id" => %{"eq" => context.administrator.id}}},
            %{"sort" => [%{"field" => "born_on", "direction" => "asc"}]}
          ] do
        text = call(context, "find_residents", arguments)
        assert text =~ "Allowed fields"
        refute text =~ "Biscuit"
      end
    end

    test "takes a filter, a sort, a limit and a kind of result, and no input", context do
      {tools, _registry} =
        AshAi.Tools.build_tools_and_registry(
          Toolbox.options(context.member, context.organisation, context.profile)
        )

      find = Enum.find(tools, &(&1.name == "find_residents"))

      assert find.parameter_schema["properties"] |> Map.keys() |> Enum.sort() ==
               ~w(after before filter limit offset result_type sort)

      assert find.parameter_schema["properties"]["filter"]["description"] =~
               "Fields: sex, name, species_label, status."

      assert get_in(find.parameter_schema, [
               "properties",
               "sort",
               "items",
               "properties",
               "field",
               "enum"
             ]) ==
               ["name", "arrived_on"]

      get = Enum.find(tools, &(&1.name == "get_task"))
      assert Map.keys(get.parameter_schema["properties"]) == ["id"]
    end

    test "gives nothing to a person who is no member", context do
      other = organisation!(context.root, "Banksia Rise")
      {_, their_admin} = member!(other, :administrator, context.root)
      {_, root_member} = member!(other, :member, their_admin)
      root_member = Ash.Seed.update!(root_member, %{root?: true})

      # A user with no organisation, a root user who is no member, and a
      # member of another organisation, also one with the root level.
      for user <- [user!(), context.root, their_admin, root_member] do
        json = call(context, user, context.organisation, "find_residents", %{})
        assert %{"results" => []} = Jason.decode!(json)
        refute json =~ "Biscuit"

        assert call(context, user, context.organisation, "find_residents", %{
                 "result_type" => "count"
               }) == "0"
      end

      # The member of the first organisation finds nothing of the other.
      assert %{"results" => []} =
               Jason.decode!(call(context, context.member, other, "find_residents", %{}))
    end

    test "gives the residents to a member whose role has no power: each role reads", context do
      {:ok, role} = Accounts.define_role(%{name: "Reader", powers: []}, context.admin)
      {reader_member, reader} = member!(context.organisation, :member, context.administrator)
      {:ok, _member} = Accounts.set_member_role(reader_member, role.id, context.admin)

      json = call(context, reader, context.organisation, "find_residents", %{})
      assert Enum.sort(names(json)) == ["Biscuit", "Clover"]
    end
  end

  describe "get_task" do
    setup context do
      task =
        plan!(context, "Evening medication", "2026-12-01T18:30", %{
          resident_ids: [context.biscuit.id],
          assignee_ids: [context.administrator.id],
          note: "With food"
        })

      {:ok, task: task}
    end

    test "gives a member one task, with its kind and what it is about", context do
      json = call(context, "get_task", %{"id" => context.task.id})
      task = Jason.decode!(json)

      assert task["id"] == context.task.id
      assert task["title"] == "Evening medication"
      assert task["state"] == "due"
      assert task["note"] == "With food"
      assert task["kind"]["label"] == "Feed"
      assert [%{"resident" => %{"name" => "Biscuit"}}] = task["subjects"]

      # Who has the task and who finished it stay on the server.
      refute Map.has_key?(task, "assignee_ids")
      refute Map.has_key?(task, "finished_by_id")
      refute json =~ context.administrator.id
    end

    test "says that an id of no task could not be found", context do
      assert call(context, "get_task", %{"id" => Ash.UUID.generate()}) =~ "could not be found"
      assert call(context, "get_task", %{"id" => "not-an-id"}) =~ "Invalid value"
      assert call(context, "get_task", %{}) =~ "id"
    end

    test "says the same to a person who is no member, and in another organisation", context do
      other = organisation!(context.root, "Banksia Rise")

      for {user, tenant} <- [
            {user!(), context.organisation},
            {context.root, context.organisation},
            {context.member, other}
          ] do
        text = call(context, user, tenant, "get_task", %{"id" => context.task.id})
        assert text =~ "could not be found"
        refute text =~ "Evening medication"
      end
    end
  end

  describe "tasks_for_day" do
    setup context do
      shed = Locations.add_location!(%{name: "Feed shed"}, context.admin)

      pair =
        Residents.form_group!(
          %{name: "The pair", resident_ids: [context.biscuit.id, context.clover.id]},
          context.admin
        )

      feed = plan!(context, "Morning feed", "2026-12-01T08:00", %{group_ids: [pair.id]})

      medicate =
        plan!(context, "Evening medication", "2026-12-01T18:30", %{
          resident_ids: [context.clover.id],
          assignee_ids: [context.administrator.id],
          note: String.duplicate("Give it with food. ", 30)
        })

      clean = plan!(context, "Clean the shed", "2026-12-01T10:00", %{location_ids: [shed.id]})
      walk = plan!(context, "Check the fence", "2026-12-01T12:00")
      {:ok, _done} = Tasks.complete_task(clean, %{}, context.admin)
      {:ok, _skipped} = Tasks.skip_task(walk, %{skip_reason: "Rain"}, context.admin)
      plan!(context, "A task of the next day", "2026-12-02T08:00")

      {:ok, shed: shed, pair: pair, feed: feed, medicate: medicate}
    end

    test "gives the tasks of the day in the order of their times, with the counts", context do
      json = call(context, "tasks_for_day", %{"date" => "2026-12-01"})
      day = Jason.decode!(json)

      assert day["date"] == "2026-12-01"
      assert day["today"] == Date.to_iso8601(Accounts.today(context.organisation))
      assert day["more"] == 0

      assert Enum.map(day["tasks"], & &1["label"]) ==
               ["Morning feed", "Clean the shed", "Check the fence", "Evening medication"]

      assert day["counts"]["done"] == 1
      assert day["counts"]["skipped"] == 1
      assert day["counts"]["due"] + day["counts"]["overdue"] == 2

      [feed, clean, _walk, medicate] = day["tasks"]

      # A reference, a label and a line of detail, with the time of the
      # organisation and its offset.
      assert feed["ref"] == "task:" <> context.feed.id
      assert feed["at"] == "2026-12-01T08:00:00+10:00"
      assert feed["detail"] =~ ~r/^08:00, (due|overdue)$/
      assert feed["kind"] == "Feed"
      assert feed["has_prescription"] == false
      assert feed["about"] == [%{"ref" => "group:" <> context.pair.id, "label" => "The pair"}]
      refute Map.has_key?(feed, "note_text")

      assert clean["state"] == "done"

      assert clean["about"] == [
               %{"ref" => "location:" <> context.shed.id, "label" => "Feed shed"}
             ]

      assert medicate["about"] ==
               [%{"ref" => "resident:" <> context.clover.id, "label" => "Clover"}]

      # The words of a person are under a key that ends in _text, and cut.
      assert String.length(medicate["note_text"]) == 301
      assert medicate["note_text"] =~ ~r/^Give it with food\. .+…$/
    end

    test "names no member", context do
      json = call(context, "tasks_for_day", %{"date" => "2026-12-01"})

      for user <- [context.administrator, context.member] do
        refute json =~ user.id
        refute json =~ to_string(user.email)
      end
    end

    test "keeps the tasks about one resident, also as a member of a group", context do
      for {resident, labels} <- [
            {context.biscuit, ["Morning feed"]},
            {context.clover, ["Morning feed", "Evening medication"]}
          ] do
        day =
          Jason.decode!(
            call(context, "tasks_for_day", %{"date" => "2026-12-01", "resident" => resident.id})
          )

        assert Enum.map(day["tasks"], & &1["label"]) == labels
        # The counts are of the tasks about the resident.
        assert day["counts"] |> Map.values() |> Enum.sum() == length(labels)
      end
    end

    test "keeps the tasks of one state, and counts the whole day", context do
      for {state, labels} <- [
            {"due", ["Morning feed", "Evening medication"]},
            {"done", ["Clean the shed"]},
            {"skipped", ["Check the fence"]},
            {"all", ["Morning feed", "Clean the shed", "Check the fence", "Evening medication"]}
          ] do
        day =
          Jason.decode!(
            call(context, "tasks_for_day", %{"date" => "2026-12-01", "state" => state})
          )

        assert Enum.map(day["tasks"], & &1["label"]) == labels
        assert day["counts"] |> Map.values() |> Enum.sum() == 4
      end
    end

    test "is the day of today with no date, in the time zone of the organisation", context do
      today = Accounts.today(context.organisation)
      plan!(context, "A task of today", "#{Date.to_iso8601(today)}T23:45")

      day = Jason.decode!(call(context, "tasks_for_day", %{}))

      assert day["date"] == Date.to_iso8601(today)
      assert [%{"label" => "A task of today", "state" => "due"}] = day["tasks"]
    end

    test "answers a wrong argument in words, and reads nothing", context do
      for {arguments, words} <- [
            {%{"date" => "tomorrow"}, "date: give a date as YYYY-MM-DD"},
            {%{"date" => 20_261_201}, "date: give a date as YYYY-MM-DD"},
            {%{"resident" => "Biscuit"}, "resident: give the id of a record"},
            {%{"state" => "late"}, "state: give one of due, done, skipped, all"}
          ] do
        text = call(context, "tasks_for_day", arguments)
        assert text =~ words
        refute text =~ "Morning feed"
      end
    end

    test "cuts a long day, and says how many more there are", context do
      for minute <- 10..54, do: plan!(context, "Task #{minute}", "2026-12-03T09:#{minute}")

      day = Jason.decode!(call(context, "tasks_for_day", %{"date" => "2026-12-03"}))

      assert length(day["tasks"]) == 40
      assert day["more"] == 5
      assert day["counts"] |> Map.values() |> Enum.sum() == 45
    end

    test "does not exist for a person who is no member, and gives nothing elsewhere", context do
      other = organisation!(context.root, "Banksia Rise")
      {_, their_admin} = member!(other, :administrator, context.root)

      for user <- [user!(), context.root, their_admin] do
        text =
          call(context, user, context.organisation, "tasks_for_day", %{"date" => "2026-12-01"})

        assert text =~ "Unknown tool"
        refute text =~ "Morning feed"
      end

      # The function refuses too, when something calls it past the list.
      {_tool, run} = Ruby.Digests.TasksForDay.tool()

      for user <- [user!(), Ruby.Actor.for(context.root), their_admin, nil] do
        assert run.(%{"date" => "2026-12-01"}, %{actor: user, tenant: context.organisation}) ==
                 {:error, "forbidden"}
      end

      # In the other organisation, their administrator reads their own day.
      day =
        Jason.decode!(
          call(context, their_admin, other, "tasks_for_day", %{"date" => "2026-12-01"})
        )

      assert day["tasks"] == []
    end

    test "runs with the name of the schema as the tenant, as a job has it", context do
      schema = "org_" <> context.organisation.id

      day =
        Jason.decode!(
          call(context, context.member, schema, "tasks_for_day", %{"date" => "2026-12-01"})
        )

      assert length(day["tasks"]) == 4
      assert hd(day["tasks"])["at"] == "2026-12-01T08:00:00+10:00"
    end
  end

  describe "an error that ash_ai does not know" do
    test "has words for the model, and no value of a record" do
      stale =
        Ash.Error.Changes.StaleRecord.exception(resource: Tasks.Task, filter: %{id: "an-id"})

      transition =
        AshStateMachine.Errors.NoMatchingTransition.exception(
          action: :complete,
          old_state: :done,
          target: :done
        )

      assert AshAi.ToToolError.to_tool_error(stale) ==
               "somebody changed this a moment ago: read it again"

      assert AshAi.ToToolError.to_tool_error(transition) ==
               "this is not in a state that allows it any more"

      for error <- [stale, transition] do
        text = AshAi.Tool.Errors.format(Ash.Error.to_error_class(error))
        refute text =~ "unexpected error"
        refute text =~ "an-id"
      end
    end
  end
end
