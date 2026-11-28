defmodule Rescord.Spike.BenchTest do
  # Scratch: times register, revise and read with and without the operation id.
  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.Residents

  @tag timeout: :infinity
  @tag :bench
  test "times" do
    root = root!()
    organisation = organisation!(root, "Bench")
    {_, administrator} = member!(organisation, :administrator, root)
    lists = lists!(organisation, root)
    admin = [actor: administrator, tenant: organisation]

    facts = %{
      breed_ids: [lists.breed.abyssinian, lists.breed.rex],
      colour_ids: [lists.colour.white, lists.colour.tan],
      temperament_ids: [lists.temperament.shy]
    }

    for i <- 1..30, do: resident!(lists, admin, Map.put(facts, :name, "W#{i}"))
    n = String.to_integer(System.get_env("BENCH_N", "300"))

    for round <- 1..3 do
      {register, residents} =
        :timer.tc(fn ->
          for i <- 1..n, do: resident!(lists, admin, Map.put(facts, :name, "R#{round}-#{i}"))
        end)

      {revise, _} =
        :timer.tc(fn ->
          for r <- residents,
              do: Residents.revise_resident!(r, %{name: "X#{r.id}" |> String.slice(0, 40)}, admin)
        end)

      {read, _} = :timer.tc(fn -> for _ <- 1..50, do: Residents.residents!(admin) end)

      IO.puts(
        "BENCH round #{round}: register #{Float.round(register / n / 1000, 3)} ms, " <>
          "revise #{Float.round(revise / n / 1000, 3)} ms, read #{Float.round(read / 50 / 1000, 3)} ms"
      )
    end

    schema = Ash.ToTenant.to_tenant(organisation, Residents.Resident)

    %{rows: rows} =
      Rescord.Repo.query!(
        """
        select c.relname, pg_total_relation_size(c.oid), c.reltuples::bigint,
               (select count(*) from information_schema.columns
                 where table_schema = $1 and table_name = c.relname and column_name = 'operation_id')
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = $1 and c.relkind = 'r'
          and c.relname in ('residents', 'resident_names', 'resident_breeds', 'arrivals')
        order by 1
        """,
        [schema]
      )

    IO.inspect(rows, label: "BENCH sizes (table, bytes, reltuples, has operation_id)")
  end
end
