defmodule Rescord.Usage.Actions do
  @moduledoc """
  Counts the actions of Ash that a person ran (ADR 0098), from the events
  that Ash emits for each action: `[:ash, <domain>, <kind>, :start]` and
  `:stop`, for a create, an update, a destroy and a generic action. A read
  does not count: the page that shows it does.

  Only an action whose actor is a user counts, so the work of a job with
  no actor, and of the assistant, which has an actor of its own, does not.
  Only the outer action of a process counts: an action that another action
  runs is a part of it. The depth is in the dictionary of the process,
  and Ash emits `:stop` also after a raise.

  The item is `<domain>.<resource>.<action>`, the short names of the code,
  such as `expenses.expense.approve`. An action counts when it ran, also
  when it refused its input: the event does not say how it ended.

  The handlers do no work but the lookup of the feature and the count. In
  the mode `off` they return at once.
  """

  alias Rescord.Usage.Features

  @kinds [:create, :update, :destroy, :action]
  @handler "rescord-usage-actions"
  @depth {__MODULE__, :depth}

  @doc "Starts to listen to the actions of Ash. A second call changes nothing."
  @spec attach() :: :ok
  def attach do
    events =
      for domain <- Application.fetch_env!(:rescord, :ash_domains),
          short = Ash.Domain.Info.short_name(domain),
          short in Features.counted_domains(),
          kind <- @kinds,
          phase <- [:start, :stop],
          do: [:ash, short, kind, phase]

    case :telemetry.attach_many(@handler, events, &__MODULE__.handle/4, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc false
  def handle([:ash, _domain, _kind, :start], _measurements, _metadata, _config) do
    Process.put(@depth, Process.get(@depth, 0) + 1)
  end

  def handle([:ash, domain, _kind, :stop], _measurements, metadata, _config) do
    case Process.get(@depth, 1) - 1 do
      0 ->
        Process.delete(@depth)
        count(domain, metadata)

      depth ->
        Process.put(@depth, depth)
    end
  end

  defp count(domain, %{actor: %Rescord.Accounts.User{}} = metadata) do
    resource = metadata[:resource_short_name]
    action = metadata[:action]

    with true <- is_atom(resource) and is_atom(action),
         feature when is_atom(feature) and not is_nil(feature) <-
           Features.of_action(domain, resource) do
      Rescord.Usage.count(feature, :action, "#{domain}.#{resource}.#{action}")
    end

    :ok
  end

  defp count(_domain, _metadata), do: :ok
end
