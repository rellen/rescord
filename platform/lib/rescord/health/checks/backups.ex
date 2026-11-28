defmodule Rescord.Health.Checks.Backups do
  @moduledoc """
  C23 of issue 38: the backups of `bin/backup` (ADR 0050), where the
  server can read their directory: `RESCORD_BACKUP_DIR`, a setting of the
  machine (ADR 0068). With no such setting it finds nothing, as a server
  cannot see a backup that another machine keeps.

    * A fault: the directory has no dump, the newest dump is older than 26
      hours, or it is empty, or the directory cannot be read.
    * A note: a partial dump a day old or more, which a backup that a
      crash stopped left (`bin/backup` removes the others, issue 38, F5).

  The count is the number of faults, or of partial dumps. No id.
  """

  use Rescord.Health.Check

  @max_age_hours 26

  @impl true
  def name, do: :backups
  @impl true
  def scope, do: :server
  @impl true
  def cadence, do: :daily
  @impl true
  def title, do: "Backups that are old or missing"

  @impl true
  def explain,
    do:
      "The newest backup of the database in RESCORD_BACKUP_DIR is missing, empty or older " <>
        "than 26 hours: look at the timer or the cron that runs bin/backup, and at its log. A " <>
        "note: a partial dump that a stopped backup left; delete it."

  @impl true
  def run(%{now: now}) do
    case Application.get_env(:rescord, :backup_dir) do
      dir when is_binary(dir) and dir != "" -> look(Path.join(dir, "database"), now)
      _none -> ok()
    end
  end

  defp look(dir, now) do
    case File.ls(dir) do
      {:ok, names} ->
        dumps = for name <- names, dump?(name), %{} = stat <- [stat(dir, name)], do: stat
        partial = for name <- names, partial?(name), %{} = stat <- [stat(dir, name)], do: stat

        cond do
          not fresh?(dumps, now) ->
            %{level: :fail, count: 1, ids: []}

          (old = Enum.count(partial, &older?(&1, now, 24))) > 0 ->
            %{level: :note, count: old, ids: []}

          true ->
            ok()
        end

      {:error, _reason} ->
        %{level: :fail, count: 1, ids: []}
    end
  end

  defp dump?(name), do: String.starts_with?(name, "rescord-") and String.ends_with?(name, ".dump")

  defp partial?(name),
    do: String.starts_with?(name, "rescord-") and String.ends_with?(name, ".dump.partial")

  defp stat(dir, name) do
    case File.stat(Path.join(dir, name), time: :posix) do
      {:ok, %File.Stat{size: size, mtime: mtime}} -> %{size: size, mtime: mtime}
      {:error, _reason} -> nil
    end
  end

  # The newest dump is there, has bytes, and is from the last 26 hours.
  defp fresh?([], _now), do: false

  defp fresh?(dumps, now) do
    newest = Enum.max_by(dumps, & &1.mtime)
    newest.size > 0 and not older?(newest, now, @max_age_hours)
  end

  defp older?(%{mtime: mtime}, now, hours), do: DateTime.to_unix(now) - mtime > hours * 3_600
end
