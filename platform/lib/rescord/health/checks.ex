defmodule Rescord.Health.Checks do
  @moduledoc """
  The checks of `Rescord.Health` (ADR 0114, issue 38), in the order that
  `/root/health` shows them. A new check goes in `all/0`, and its name in
  `names/0`: the list of names is a literal, so that the attribute `check`
  of `Rescord.Health.Result` can name them when it compiles.
  """

  alias Rescord.Health.Checks

  @doc "The modules of the checks."
  @spec all() :: [module]
  def all do
    [
      Checks.RoutinesBehind,
      Checks.RoutineAfterPrescription,
      Checks.DoseTasks,
      Checks.RubyReplies,
      Checks.RubyRetention,
      Checks.Vault,
      Checks.SecretsSet,
      Checks.Managers,
      Checks.RootUsers,
      Checks.Jobs,
      Checks.Cron,
      Checks.Migrations,
      Checks.Clock
    ]
  end

  @doc "The names of the checks, in the order of `all/0`."
  @spec names() :: [atom]
  def names do
    [
      :routines_behind,
      :routine_after_prescription,
      :dose_tasks,
      :ruby_replies,
      :ruby_retention,
      :vault,
      :secrets_set,
      :managers,
      :root_users,
      :jobs,
      :cron,
      :migrations,
      :clock
    ]
  end

  @doc "The check with `name`, or nil."
  @spec find(atom) :: module | nil
  def find(name), do: Enum.find(all(), &(&1.name() == name))
end
