defmodule Rescord.Spike.OperationIdTest do
  # Scratch: what the operation id of AshPaperTrail does in rescord.
  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  require Ash.Query

  alias Rescord.{Accounts, Locations, Repo, Residents, Tasks}

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    lists = lists!(organisation, root)
    admin = [actor: administrator, tenant: organisation]
    {:ok, root: root, organisation: organisation, admin: admin, lists: lists}
  end

  defp schema(organisation), do: Ash.ToTenant.to_tenant(organisation, Residents.Resident)

  # Each version row of each table of a schema that has an operation id column:
  # {table, operation id, action}. The ground truth, with no Ash in between.
  defp trail(schema) do
    %{rows: tables} =
      Repo.query!(
        "select table_name from information_schema.columns where table_schema = $1 and column_name = 'operation_id' order by 1",
        [schema]
      )

    Enum.flat_map(tables, fn [table] ->
      %{rows: rows} =
        Repo.query!(
          ~s(select operation_id::text, version_action_name from "#{schema}"."#{table}")
        )

      for [id, action] <- rows, do: {table, id, action}
    end)
  end

  # The version rows that `fun` wrote, grouped by operation id.
  defp written(schema, fun) do
    before = Enum.frequencies(trail(schema))
    result = fun.()

    groups =
      trail(schema)
      |> Enum.frequencies()
      |> Enum.flat_map(fn {row, count} ->
        List.duplicate(row, count - Map.get(before, row, 0))
      end)
      |> Enum.group_by(&elem(&1, 1), fn {table, _id, action} -> "#{table}.#{action}" end)
      |> Enum.map(fn {id, rows} -> {id, Enum.sort(rows)} end)

    {result, groups}
  end

  defp show(label, groups) do
    IO.puts("\nSPIKE #{label}: #{length(groups)} operation id(s)")
    for {id, rows} <- groups, do: IO.puts("  #{inspect(id)} #{Enum.join(rows, ", ")}")
    groups
  end

  defp given(id), do: [context: %{shared: %{ash_paper_trail: %{operation_id: id}}}]

  test "1. one action with no nested action", context do
    {shed, groups} =
      written(schema(context.organisation), fn ->
        Locations.add_location!(%{name: "Main shed"}, context.admin)
      end)

    assert [{id, ["locations.add"]}] = show("add_location", groups)
    assert {:ok, _} = Ecto.UUID.cast(id)
    # UUID version 7
    assert String.at(id, 14) == "7"

    # The version resource of Ash reads it too.
    assert [version] =
             Locations.Location.Version
             |> Ash.Query.filter(id == ^shed.id)
             |> Ash.read!(tenant: context.organisation, authorize?: false)

    assert version.operation_id == id

    # A change as of a later instant.
    later = DateTime.add(DateTime.utc_now(), 2, :day)

    {_, groups} =
      written(schema(context.organisation), fn ->
        Locations.revise_location!(shed, %{name: "Big shed"}, context.admin ++ [as_of: later])
      end)

    assert [{other, ["locations.revise"]}] = show("revise_location as of later", groups)
    assert other != id

    # An id that the caller gives.
    mine = Ash.UUIDv7.generate()

    {_, groups} =
      written(schema(context.organisation), fn ->
        Locations.add_location!(%{name: "Hutch"}, context.admin ++ given(mine))
      end)

    assert [{^mine, ["locations.add"]}] = show("add_location with a given id", groups)
  end

  test "2. register and revise a resident: the facts are nested actions", context do
    facts = %{
      breed_ids: [context.lists.breed.abyssinian, context.lists.breed.rex],
      colour_ids: [context.lists.colour.white]
    }

    {fern, groups} =
      written(schema(context.organisation), fn ->
        resident!(context.lists, context.admin, Map.put(facts, :name, "Fern"))
      end)

    show("register_resident", groups)

    {_, groups} =
      written(schema(context.organisation), fn ->
        Residents.revise_resident!(
          fern,
          %{name: "Ferny", colour_ids: [context.lists.colour.tan]},
          context.admin
        )
      end)

    show("revise_resident", groups)

    mine = Ash.UUIDv7.generate()

    {_, groups} =
      written(schema(context.organisation), fn ->
        resident!(context.lists, context.admin ++ given(mine), Map.put(facts, :name, "Sage"))
      end)

    show("register_resident with a given id #{mine}", groups)
  end

  test "3. remove a resident: nested actions and signal listeners", context do
    admin = context.admin
    shed = Locations.add_location!(%{name: "Main shed"}, admin)
    fern = resident!(context.lists, admin, %{name: "Fern", sex: :female})
    sage = resident!(context.lists, admin, %{name: "Sage", sex: :female})
    for r <- [fern, sage], do: {:ok, _} = Locations.settle({:resident, r.id}, shed.id, admin)
    _group = Residents.form_group!(%{name: "Pair", resident_ids: [fern.id, sage.id]}, admin)

    due = DateTime.add(DateTime.utc_now(), 1, :hour)
    _alone = Tasks.plan_task!(%{title: "Weigh", due_at: due, resident_ids: [fern.id]}, admin)

    _both =
      Tasks.plan_task!(%{title: "Clean", due_at: due, resident_ids: [fern.id, sage.id]}, admin)

    time = Time.truncate(Time.add(Time.utc_now(), 6, :hour), :second)

    _routine =
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

    {:ok, groups} =
      written(schema(context.organisation), fn ->
        Residents.remove_resident(fern, admin)
      end)

    show("remove_resident", groups)

    %{rows: rows} =
      Repo.query!(
        ~s|select version_action_name, operation_id::text, upper(valid_at) is not null from "#{schema(context.organisation)}".placements where resident_id = $1|,
        [Ecto.UUID.dump!(fern.id)]
      )

    IO.inspect(rows, label: "SPIKE the placement of the removed resident (action, id, ended)")
    IO.inspect(Enum.map(groups, &elem(&1, 0)), label: "SPIKE the id of the removal")
  end

  test "4. bulk actions", context do
    tenant = [tenant: context.organisation, authorize?: false]
    inputs = for i <- 1..250, do: %{name: "Pen #{i}"}

    {result, groups} =
      written(schema(context.organisation), fn ->
        Ash.bulk_create(inputs, Locations.Location, :add, tenant ++ [return_errors?: true])
      end)

    assert result.status == :success

    show(
      "bulk_create of 250 (batch size 100)",
      Enum.map(groups, fn {id, r} -> {id, ["#{length(r)} rows"]} end)
    )

    mine = Ash.UUIDv7.generate()

    {result, groups} =
      written(schema(context.organisation), fn ->
        Ash.bulk_create(
          for(i <- 1..250, do: %{name: "Run #{i}"}),
          Locations.Location,
          :add,
          tenant ++ [return_errors?: true] ++ given(mine)
        )
      end)

    assert result.status == :success

    show(
      "bulk_create of 250 with a given id",
      Enum.map(groups, fn {id, r} -> {id, ["#{length(r)} rows"]} end)
    )

    for strategy <- [:atomic, :atomic_batches, :stream] do
      {result, groups} =
        written(schema(context.organisation), fn ->
          Locations.Location
          |> Ash.Query.filter(contains(name, "Pen"))
          |> Ash.bulk_update(
            :revise,
            %{capacity: :erlang.phash2(strategy, 50) + 2},
            tenant ++ [strategy: strategy, return_errors?: true]
          )
        end)

      show(
        "bulk_update of 250, strategy #{strategy}: #{result.status} #{inspect(result.errors)}",
        Enum.map(groups, fn {id, r} -> {id, ["#{length(r)} rows"]} end)
      )
    end
  end

  test "5. two organisations", context do
    other = organisation!(context.root, "Banksia")
    a = schema(context.organisation)
    b = schema(other)

    {_, in_a} =
      written(a, fn ->
        Locations.add_location!(%{name: "Shed"}, context.admin)
      end)

    {_, in_b} =
      written(b, fn ->
        Locations.add_location!(%{name: "Shed"}, actor: context.root, tenant: other)
      end)

    assert [{id_a, _}] = show("organisation a", in_a)
    assert [{id_b, _}] = show("organisation b", in_b)
    assert id_a != id_b

    # One given id in two organisations: each schema holds its own row.
    mine = Ash.UUIDv7.generate()

    {_, in_a} =
      written(a, fn ->
        {_, in_b} =
          written(b, fn ->
            Locations.add_location!(%{name: "Yard"}, context.admin ++ given(mine))

            Locations.add_location!(
              %{name: "Yard"},
              [actor: context.root, tenant: other] ++ given(mine)
            )
          end)

        show("organisation b, given id", in_b)
      end)

    show("organisation a, given id", in_a)
  end

  test "6. a task: a resource that is not temporal, with a version table", context do
    admin = context.admin
    fern = resident!(context.lists, admin, %{name: "Fern", sex: :female})
    due = DateTime.add(DateTime.utc_now(), 1, :hour)

    {task, groups} =
      written(schema(context.organisation), fn ->
        Tasks.plan_task!(%{title: "Weigh", due_at: due, resident_ids: [fern.id]}, admin)
      end)

    show("plan_task", groups)

    {_, groups} =
      written(schema(context.organisation), fn ->
        Tasks.complete_task!(task, %{note: "Done"}, admin)
      end)

    show("complete_task", groups)
  end

  test "8. a function of a domain that runs two actions, with a given id", context do
    admin = context.admin
    shed = Locations.add_location!(%{name: "Shed"}, admin)
    yard = Locations.add_location!(%{name: "Yard"}, admin)
    pen = Locations.add_location!(%{name: "Pen"}, admin)
    {:ok, _} = Locations.move_location(pen, shed.id, admin)

    {{:ok, _}, groups} =
      written(schema(context.organisation), fn ->
        Locations.move_location(pen, yard.id, admin)
      end)

    show("move_location, no id given", groups)
    mine = Ash.UUIDv7.generate()

    {{:ok, _}, groups} =
      written(schema(context.organisation), fn ->
        Locations.move_location(pen, shed.id, admin ++ given(mine))
      end)

    show("move_location, id given #{mine}", groups)
  end

  test "7. the public schema: an organisation and its first member", context do
    {_, groups} =
      written("public", fn ->
        other = organisation!(context.root, "Banksia")
        member!(other, :administrator, context.root)
      end)

    show("create_organisation and invite, public schema", groups)
  end
end
