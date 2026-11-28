defmodule Rescord.Health.Checks.VersionIds do
  @moduledoc """
  C19 of issue 38: a version of the history written in the last day with
  no correlation id or no operation id, or with a causation id that is its
  own operation id (ADR 0101). Each action that writes a version gets the
  ids; a version without them is a fault of the code, which the timeline
  of the history cannot put with its piece of work. Versions from before
  ADR 0101 have no ids, so it reads only the last day.

  It reads each table of the schema of the organisation that has the
  columns of the ids: the tables of versions (`*_versions`, by
  `version_inserted_at`) and the temporal tables (by the start of
  `valid_at`). A note, since only a change to the code puts it right. The
  ids are those of the versions.
  """

  use Rescord.Health.Check

  @impl true
  def name, do: :version_ids
  @impl true
  def scope, do: :organisation
  @impl true
  def cadence, do: :daily
  @impl true
  def title, do: "History with no ids of its work"

  @impl true
  def explain,
    do:
      "A change of the last day is in the history with no id of the work that made it, so " <>
        "the history cannot show it with the rest of that work. Nothing is lost: report it, " <>
        "with the ids and the time."

  @impl true
  def run(%{prefix: prefix, now: now} = context) do
    %{rows: rows} =
      Rescord.Repo.query!(
        """
        select c.table_name, bool_or(c.column_name = 'version_inserted_at')
        from information_schema.columns c
        where c.table_schema = $1
          and c.column_name in ('operation_id', 'version_inserted_at', 'valid_at')
          and exists (select 1 from information_schema.columns o
            where o.table_schema = c.table_schema and o.table_name = c.table_name
              and o.column_name = 'operation_id')
          and exists (select 1 from information_schema.columns o
            where o.table_schema = c.table_schema and o.table_name = c.table_name
              and o.column_name in ('version_inserted_at', 'valid_at'))
        group by c.table_name
        order by c.table_name
        """,
        [prefix]
      )

    case rows do
      [] ->
        ok()

      tables ->
        tables
        |> Enum.map_join("\nunion all\n", fn [name, versions?] ->
          select(context, name, versions?)
        end)
        |> query([DateTime.to_naive(now), now])
        |> found(:note)
    end
  end

  @missing "(v.correlation_id is null or v.operation_id is null or v.causation_id = v.operation_id)"

  defp select(context, name, true) do
    "select v.id from #{table(context, name)} v " <>
      "where v.version_inserted_at > $1::timestamp - interval '1 day' and #{@missing}"
  end

  # A temporal table holds its history in its rows: a row of the last day
  # is a version of the last day.
  defp select(context, name, false) do
    "select v.id from #{table(context, name)} v " <>
      "where lower(v.valid_at) > $2::timestamptz - interval '1 day' and #{@missing}"
  end
end
