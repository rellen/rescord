defmodule Rescord.Repo.Migrations.AddTheCountEstimateOfObanMet do
  @moduledoc """
  Adds the function `oban_count_estimate(state, queue)`, with which Oban
  Met, the part of Oban Web that gathers the counts, estimates the number
  of jobs of a state and a queue from the plan of the query (ADR 0110).

  Oban Met would make this function itself while the server runs. Rescord
  turns that off (`auto_migrate: false` of its reporter in
  `config/config.exs`), so that the schema changes only in a migration,
  which the start rehearses (ADR 0081). The SQL is the one of
  `Oban.Met.Migration` of `oban_met` 1.3.3, written out here, so that a new
  version of the package cannot change what this migration did.

  It adds a function and changes no row.
  """

  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION public.oban_count_estimate(state text, queue text)
    RETURNS integer AS $func$
    DECLARE
      plan jsonb;
    BEGIN
      EXECUTE 'EXPLAIN (FORMAT JSON)
               SELECT id
               FROM public.oban_jobs
               WHERE state = $1::public.oban_job_state
               AND queue = $2'
        INTO plan
        USING state, queue;
      RETURN plan->0->'Plan'->'Plan Rows';
    END;
    $func$
    LANGUAGE plpgsql
    """
  end

  def down do
    execute "DROP FUNCTION IF EXISTS public.oban_count_estimate(text, text)"
  end
end
