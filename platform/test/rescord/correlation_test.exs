defmodule Rescord.CorrelationTest do
  @moduledoc """
  Holds the rule of ADR 0101: each version that one action writes, with the
  versions of its nested actions and of its listeners, has one correlation
  id.

  The tests read the columns `correlation_id` of each table of the schema of
  the organisation, with no Ash in between: a nested action that loses the
  shared context writes a version with an id of its own and no error, so
  only the rows show it.

  Each test creates an organisation, so the tests do not run beside others.
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.StorageFixtures

  alias Rescord.{Accounts, Correlation, Journal, Locations, Repo, Residents, Tasks}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    disk_store!(tmp_dir)
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    lists = lists!(organisation, root)
    admin = [actor: administrator, tenant: organisation]

    {:ok,
     organisation: organisation,
     schema: Ash.ToTenant.to_tenant(organisation, Residents.Resident),
     admin: admin,
     lists: lists}
  end

  # Each version of each table of the schema:
  # {table, correlation id, action, operation id, causation id}.
  defp versions(schema) do
    %{rows: tables} =
      Repo.query!(
        """
        select table_name from information_schema.columns
        where table_schema = $1 and column_name = 'correlation_id'
        order by 1
        """,
        [schema]
      )

    for [table] <- tables,
        [id, action, operation, cause] <-
          Repo.query!(
            ~s(select correlation_id::text, version_action_name, operation_id::text, ) <>
              ~s(causation_id::text from "#{schema}"."#{table}")
          ).rows,
        do: {table, id, action, operation, cause}
  end

  # The versions that `fun` wrote, as a map from each correlation id to its
  # versions, "table.action". `chain/1` reads the rows themselves.
  defp written(schema, fun) do
    before = Enum.frequencies(versions(schema))
    result = fun.()

    new =
      schema
      |> versions()
      |> Enum.frequencies()
      |> Enum.flat_map(fn {row, count} ->
        List.duplicate(row, count - Map.get(before, row, 0))
      end)

    Process.put(:written, new)

    {result,
     Enum.group_by(new, &elem(&1, 1), fn {table, _id, action, _op, _cause} ->
       "#{table}.#{action}"
     end)}
  end

  defp one_id!(groups) do
    assert [{id, versions}] = Map.to_list(groups),
           "more than one correlation id: #{inspect(groups)}"

    assert {:ok, _uuid} = Ecto.UUID.cast(id)
    {id, Enum.sort(versions)}
  end

  # The rows of the last `written/2`, by "table.action": {operation id, causation id}.
  defp chain do
    Enum.group_by(
      Process.get(:written),
      fn {table, _id, action, _op, _cause} -> "#{table}.#{action}" end,
      fn {_table, _id, _action, op, cause} -> {op, cause} end
    )
  end

  defp given(id), do: [context: %{shared: %{ash_paper_trail: %{operation_id: id}}}]

  test "the registration of a resident writes each of its facts with one id", context do
    {_resident, groups} =
      written(context.schema, fn ->
        resident!(context.lists, context.admin, %{
          name: "Fern",
          breed_ids: [context.lists.breed.abyssinian, context.lists.breed.rex],
          colour_ids: [context.lists.colour.white]
        })
      end)

    {_id, versions} = one_id!(groups)

    assert versions == [
             "arrivals.record",
             "resident_breeds.add",
             "resident_breeds.add",
             "resident_colours.add",
             "resident_desex_statuses.set",
             "resident_names.set",
             "residents.register"
           ]
  end

  test "an id that the caller gives reaches each nested action", context do
    id = Ash.UUIDv7.generate()

    {_resident, groups} =
      written(context.schema, fn ->
        resident!(context.lists, context.admin ++ given(id), %{name: "Fern"})
      end)

    assert {^id, [_ | _]} = one_id!(groups)
  end

  test "the removal of a resident and each listener write one id", context do
    admin = context.admin
    shed = Locations.add_location!(%{name: "Main shed"}, admin)
    fern = resident!(context.lists, admin, %{name: "Fern", sex: :female})
    sage = resident!(context.lists, admin, %{name: "Sage", sex: :female})
    {:ok, _placement} = Locations.settle({:resident, fern.id}, shed.id, admin)

    due = DateTime.add(DateTime.utc_now(), 1, :hour)
    Tasks.plan_task!(%{title: "Weigh", due_at: due, resident_ids: [fern.id]}, admin)
    Tasks.plan_task!(%{title: "Clean", due_at: due, resident_ids: [fern.id, sage.id]}, admin)
    time = Time.truncate(Time.add(Time.utc_now(), 6, :hour), :second)

    Tasks.start_routine!(
      %{
        title: "Hay",
        pattern: :daily,
        times: [%{time | second: 0}],
        starts_on: Accounts.today(context.organisation),
        resident_ids: [fern.id, sage.id]
      },
      admin
    )

    {:ok, groups} = written(context.schema, fn -> Residents.remove_resident(fern, admin) end)
    {_id, versions} = one_id!(groups)

    # The removal, the routine that forgets the resident, the subjects that
    # are dropped, and the task left with no subject that is skipped. The
    # placement ends with no version (ADR 0012), so it has no row here.
    assert "residents.remove" in versions
    assert "routines_versions.forget_resident" in versions
    assert "task_subjects_versions.drop" in versions
    assert "tasks_versions.skip_left_alone" in versions

    # The removal caused the routine and the subjects, and the drop of the
    # subjects caused the skip of the task.
    chain = chain()
    assert [{removal, nil}] = chain["residents.remove"]
    assert [{_routine, ^removal}] = chain["routines_versions.forget_resident"]
    [{drop, ^removal} | _] = subjects = chain["task_subjects_versions.drop"]
    # One bulk call: each subject has the same operation id.
    assert Enum.uniq(subjects) == [{drop, removal}]
    assert [{skip, ^drop}] = chain["tasks_versions.skip_left_alone"]
    assert Enum.uniq([removal, drop, skip]) |> length() == 3
  end

  test "a task and its subjects are planned with one id", context do
    fern = resident!(context.lists, context.admin, %{name: "Fern"})
    due = DateTime.add(DateTime.utc_now(), 1, :hour)

    {_task, groups} =
      written(context.schema, fn ->
        Tasks.plan_task!(%{title: "Weigh", due_at: due, resident_ids: [fern.id]}, context.admin)
      end)

    assert {_id, ["task_subjects_versions.add", "tasks_versions.plan"]} = one_id!(groups)

    chain = chain()
    assert [{plan, nil}] = chain["tasks_versions.plan"]
    assert [{subject, ^plan}] = chain["task_subjects_versions.add"]
    assert subject != plan
  end

  test "the completion of a task writes its dose with one id", context do
    fern = resident!(context.lists, context.admin, %{name: "Fern"})

    prescription =
      Journal.write_entry!(
        %{
          resident_id: fern.id,
          kind: :prescription,
          medication: "A sample antibiotic",
          dose: "0.2 mL two times each day"
        },
        context.admin
      )

    {:ok, %{prescription: %{id: prescription_id}}} =
      Journal.entry_with_facts(prescription.id, context.admin)

    task =
      Tasks.plan_task!(
        %{
          title: "Medicate",
          due_at: DateTime.add(DateTime.utc_now(), 1, :hour),
          prescription_id: prescription_id,
          resident_ids: [fern.id]
        },
        context.admin
      )

    {{:ok, _done}, groups} =
      written(context.schema, fn -> Tasks.complete_task(task, %{}, context.admin) end)

    {_id, versions} = one_id!(groups)
    assert "tasks_versions.complete" in versions
    assert Enum.any?(versions, &String.starts_with?(&1, "journal_entries."))

    # The completion caused the entry of the dose.
    chain = chain()
    assert [{completion, nil}] = chain["tasks_versions.complete"]
    entries = for {"journal_entries." <> _, rows} <- chain, row <- rows, do: row
    assert [{_entry, ^completion}] = entries
  end

  test "a function of a domain that runs several actions writes one id", context do
    fern = resident!(context.lists, context.admin, %{name: "Fern"})

    {{:ok, _entry}, groups} =
      written(context.schema, fn ->
        Journal.write_entry_with_files(
          %{resident_id: fern.id, kind: :general, note: "In the garden."},
          [{"one.jpg", photo()}, {"two.jpg", photo()}],
          context.admin
        )
      end)

    {_id, versions} = one_id!(groups)
    assert Enum.count(versions, &String.starts_with?(&1, "journal_attachments")) == 2
    assert Enum.any?(versions, &String.starts_with?(&1, "journal_entries"))
  end

  test "start/1 keeps an id that the options hold" do
    id = Ash.UUIDv7.generate()
    assert Correlation.start([tenant: "t"] ++ given(id)) == [tenant: "t"] ++ given(id)

    opts = Correlation.start(tenant: "t")
    assert opts[:tenant] == "t"
    assert %{shared: %{ash_paper_trail: %{operation_id: new}}} = opts[:context]

    assert new != id
  end

  # The changes that pass a tenant to a call and need no context, each with
  # its reason.
  @no_context %{
    # It reads a role, and writes nothing.
    "lib/rescord/accounts/changes/set_role.ex" => :read,
    # It reads the snapshot of a resident, and writes nothing.
    "lib/rescord/transfers/changes/send_transfer.ex" => :read,
    # It runs in a job, and the resources of a conversation keep no paper
    # trail (ADR 0069).
    "lib/rescord/ruby/changes/respond.ex" => :no_trail
  }

  # A new change that builds the options of a nested action and forgets the
  # context writes versions with ids of their own, and no other test fails.
  # A validation, a check and a calculation only read, so only the changes
  # count.
  test "each change that passes a tenant to a call gives the context" do
    for path <- Path.wildcard("lib/**/changes/*.ex"),
        not Map.has_key?(@no_context, path),
        source = File.read!(path),
        tenants = length(Regex.scan(~r/\btenant: [a-z_.]*tenant\b/, source)),
        tenants > 0 do
      contexts =
        length(Regex.scan(~r/context: Rescord\.Correlation\.context\(changeset\)/, source))

      assert contexts >= tenants,
             "#{path} passes a tenant to a call with no " <>
               "`context: Rescord.Correlation.context(changeset)` (ADR 0101). " <>
               "A change that only reads goes in @no_context of this test, with the reason."
    end
  end
end
