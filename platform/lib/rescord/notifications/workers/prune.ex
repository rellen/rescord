defmodule Rescord.Notifications.Workers.Prune do
  @moduledoc """
  Deletes the old notifications of each organisation, each night
  (`Rescord.Notifications.prune/2`): 30 days after a person read one, and
  90 days after it was made.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()

    for organisation <- Rescord.Accounts.all_organisations() do
      try do
        Rescord.Notifications.prune(organisation, now)
      rescue
        error ->
          Logger.error(
            "The old notifications of the organisation #{organisation.id} stay: " <>
              Rescord.Log.reason(error)
          )
      end
    end

    :ok
  end
end
