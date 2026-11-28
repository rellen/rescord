defmodule Rescord.Changes do
  @moduledoc """
  What a page hears when a record of its organisation changes (ADR 0096).

  Each resource has the notifier `Ash.Notifier.PubSub`, which
  `Rescord.Resource` sets up. After a create, an update or a destroy has
  committed, the notifier calls `broadcast/3` here, and this module sends a
  `Rescord.Changes.Change` to each process that listens for the domain of
  the resource in that organisation.

  ## A change says that something changed, and not what

  A `Change` names the domain, the resource, the action and the primary key.
  It holds no attribute of the record. A process that hears one reads again,
  as its own actor, through the code interface of the domain, so the
  policies decide what it sees, as for any read. Nothing here goes to a
  browser.

  ## A topic is one domain of one organisation

      changes:org_<id>:tasks       a resource in the schema of an organisation
      changes:<id>:transfers       a resource that organisations share

  A resource in the schema of an organisation names the organisation by its
  tenant, and a shared resource by an attribute that holds the id of the
  organisation, so there are two spellings. `topics/2` gives both, and
  `subscribe/2` listens to both. A process never hears a change of another
  organisation, because it subscribes with its own organisation only.

  ## The process that wrote does not hear its own change

  `broadcast/3` runs in the process that ran the action, and leaves that
  process out: it has the result in its hands already. A page that writes
  reads again by itself, as it did before there was a notifier.

  The core may use `Phoenix.PubSub` (ADR 0009). It cannot name the endpoint,
  which is why the notifier calls this module.
  """

  alias Ash.Notifier.Notification

  @pubsub Rescord.PubSub
  @prefix "changes"

  defmodule Change do
    @moduledoc """
    One change of one record: which domain and resource, which action, and
    the primary key. It has no attribute of the record (ADR 0096).
    """

    @enforce_keys [:domain, :resource, :action, :type, :id]
    defstruct [:domain, :resource, :action, :type, :id]

    @type t :: %__MODULE__{
            domain: module(),
            resource: module(),
            action: atom(),
            type: :create | :update | :destroy,
            id: term()
          }
  end

  @doc "The name of the PubSub server that carries the changes."
  @spec pubsub() :: atom()
  def pubsub, do: @pubsub

  @doc "The prefix of each topic, which `Rescord.Resource` gives to the notifier."
  @spec prefix() :: String.t()
  def prefix, do: @prefix

  @doc """
  The part of a topic that names a domain: `"tasks"` for `Rescord.Tasks`.
  """
  @spec key(module()) :: String.t()
  def key(domain) when is_atom(domain) do
    domain |> Module.split() |> List.last() |> Macro.underscore()
  end

  @doc """
  The topics of `domain` in `organisation`: one for the resources in the
  schema of the organisation, and one for the resources that organisations
  share.
  """
  @spec topics(struct(), module()) :: [String.t()]
  def topics(%{id: id} = organisation, domain) when is_binary(id) and is_atom(domain) do
    key = key(domain)
    # The tenant of a resource is the name of the schema of the organisation,
    # and the notifier puts it in the topic. The implementation of
    # `Ash.ToTenant` takes no account of the resource.
    tenant = Ash.ToTenant.to_tenant(organisation, nil)

    Enum.uniq(["#{@prefix}:#{tenant}:#{key}", "#{@prefix}:#{id}:#{key}"])
  end

  @doc """
  Subscribes the calling process to the changes of `domains` in
  `organisation`. A LiveView uses `RescordWeb.LiveChanges.listen/3` in its
  place, which also waits a moment and reads once for several changes.
  """
  @spec subscribe(struct(), [module()]) :: :ok
  def subscribe(organisation, domains) when is_list(domains) do
    for domain <- domains, topic <- topics(organisation, domain) do
      :ok = Phoenix.PubSub.subscribe(@pubsub, topic)
    end

    :ok
  end

  @doc """
  The `Change` of a notification. It is the `transform` of each resource, so
  that no record leaves the process that wrote it.
  """
  @spec change(Notification.t()) :: Change.t()
  def change(%Notification{resource: resource, action: action, data: data} = notification) do
    %Change{
      domain: notification.domain || Ash.Resource.Info.domain(resource),
      resource: resource,
      action: action.name,
      type: action.type,
      id: primary_key(resource, data)
    }
  end

  defp primary_key(resource, data) do
    case Ash.Resource.Info.primary_key(resource) do
      [field] -> Map.get(data, field)
      fields -> Map.take(data, fields)
    end
  end

  @doc """
  Sends a change to each process that listens to `topic`, except the process
  that calls. `Ash.Notifier.PubSub` calls it after the action has committed.

  It sends a `Change` and nothing else: a resource whose publication has a
  `transform` of its own that returns something else raises here, in the
  process that wrote.
  """
  @spec broadcast(String.t(), String.t(), Change.t()) :: :ok
  def broadcast(@prefix <> ":" <> _rest = topic, _event, %Change{} = change) do
    Phoenix.PubSub.broadcast_from(@pubsub, self(), topic, change)
  end
end
