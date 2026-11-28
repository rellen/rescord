defmodule Rescord.Repo.TenantMigrations.AddTheStandardUnitOfAMeasureKind do
  @moduledoc """
  Gives a measure kind its standard unit (ADR 0094): the column
  `standard_unit_id` of `measure_kinds`, which names a unit of the
  organisation, or nothing.

  The column is empty at first. The migration then fills it for a kind
  where the answer is no guess, in each version of the row of that kind:

    1. A kind that names exactly one unit gets that unit.
    2. Otherwise, a kind whose measurements all have one and the same
       unit, and none without a unit, gets that unit, when the kind names
       no unit or names that one.

  Each other kind keeps no standard unit, and an administrator chooses one
  on the page of the lists. The rules read the rows as they are now: the
  newest version of a kind, and each measurement that is not corrected
  away and not removed.

  The migration changes no measurement, and writes nothing else. SQL
  writes nothing in the history of a kind. A second run changes nothing: a
  kind with a standard unit stays as it is.

  `down` removes the column, with each standard unit that an administrator
  chose since.
  """

  use Ecto.Migration

  def up do
    alter table(:measure_kinds, prefix: prefix()) do
      add :standard_unit_id, :uuid
    end

    for statement <- fill(prefix()), do: execute(statement)
  end

  def down do
    alter table(:measure_kinds, prefix: prefix()) do
      remove :standard_unit_id
    end
  end

  @doc "The statements that fill the standard unit, for the schema of one organisation."
  def fill(prefix) do
    [
      # 1. The one unit of a kind.
      """
      UPDATE "#{prefix}"."measure_kinds" AS kind
      SET standard_unit_id = now_kind.unit_ids[1]
      FROM "#{prefix}"."measure_kinds" AS now_kind
      WHERE now_kind.id = kind.id
        AND upper_inf(now_kind.valid_at)
        AND cardinality(now_kind.unit_ids) = 1
        AND kind.standard_unit_id IS NULL
        AND EXISTS (
          SELECT 1 FROM "#{prefix}"."units" AS unit WHERE unit.id = now_kind.unit_ids[1]
        )
      """,
      # 2. The one unit that each measurement of a kind has.
      """
      UPDATE "#{prefix}"."measure_kinds" AS kind
      SET standard_unit_id = used.unit_id
      FROM "#{prefix}"."measure_kinds" AS now_kind,
           (
             SELECT measurement.measure_kind_id,
                    (array_agg(DISTINCT measurement.unit_id))[1] AS unit_id
             FROM "#{prefix}"."measurements" AS measurement
             WHERE upper_inf(measurement.valid_at) AND measurement.archived_at IS NULL
             GROUP BY measurement.measure_kind_id
             HAVING count(DISTINCT measurement.unit_id) = 1
                AND count(*) = count(measurement.unit_id)
           ) AS used
      WHERE now_kind.id = kind.id
        AND upper_inf(now_kind.valid_at)
        AND used.measure_kind_id = kind.id
        AND kind.standard_unit_id IS NULL
        AND (cardinality(now_kind.unit_ids) = 0 OR used.unit_id = ANY (now_kind.unit_ids))
      """
    ]
  end
end
