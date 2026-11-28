defmodule Rescord.Usage.Features do
  @moduledoc """
  The fixed list of the features that the usage counts name (ADR 0098),
  and the feature of each action of Ash.

  A count names a feature of this list, never a word that a browser sent.
  The web layer maps its pages and its file routes to these keys
  (`RescordWeb.Usage`), and words each one (`RescordWeb.UsageWords`).
  `Rescord.UsageTest` fails for a domain or a resource with no feature and
  no reason to leave it out, and `RescordWeb.UsageTest` for a page or a
  file route.
  """

  @features [
    :organisation,
    :residents,
    :groups,
    :housing,
    :journal,
    :conditions,
    :measurements,
    :timeline,
    :photos,
    :tasks,
    :routines,
    :comments,
    :notifications,
    :calendar,
    :inventory,
    :expenses,
    :reports,
    :transfers,
    :export,
    :tools,
    :assistant,
    :lists,
    :members,
    :settings,
    :server
  ]

  @typedoc "A key of the list."
  @type t :: atom

  # The feature of each domain, and of each resource that is not of the
  # feature of its domain. `nil` leaves the resource out, with the reason.
  @domains %{
    accounts: :members,
    calendars: :calendar,
    comments: :comments,
    expenses: :expenses,
    inventory: :inventory,
    journal: :journal,
    lists: :lists,
    locations: :housing,
    notifications: :notifications,
    photos: :photos,
    # The requests to erase data are a part of the members (ADR 0105).
    privacy: :members,
    reports: :reports,
    residents: :residents,
    ruby: :assistant,
    tasks: :tasks,
    transfers: :transfers
  }

  @resources %{
    {:accounts, :organisation} => :settings,
    {:accounts, :user} => :server,
    # The sign-in: it says who works, and when.
    {:accounts, :token} => nil,
    {:journal, :episode} => :conditions,
    {:notifications, :settings} => :server,
    {:privacy, :instance_settings} => :server,
    {:journal, :diagnosis} => :conditions,
    {:journal, :measurement} => :measurements,
    {:residents, :family} => :groups,
    {:residents, :family_member} => :groups,
    {:residents, :group} => :groups,
    {:residents, :group_member} => :groups,
    {:tasks, :routine} => :routines
  }

  # The domains whose actions are never counted, with the reason.
  @left_out %{
    # Its own writes: a count of the counts.
    usage: "the usage counts themselves",
    # It reads the database with SQL, and runs no action of a person.
    health: "the sanity checks of the server, which run on their own"
  }

  @doc "Each feature, in the order of the page."
  @spec all() :: [t]
  def all, do: @features

  @doc "Whether `feature` is a key of the list."
  @spec feature?(term) :: boolean
  def feature?(feature), do: feature in @features

  @doc """
  The feature of an action of a resource, by the short names of its domain
  and its resource, or `nil` for one that is not counted.
  """
  @spec of_action(atom, atom) :: t | nil
  def of_action(domain, resource) do
    case Map.fetch(@resources, {domain, resource}) do
      {:ok, feature} -> feature
      :error -> Map.get(@domains, domain)
    end
  end

  @doc "The domains that have a feature, by their short names."
  @spec counted_domains() :: [atom]
  def counted_domains, do: Map.keys(@domains)

  @doc "The domains that are left out on purpose, with the reason."
  @spec left_out_domains() :: %{atom => String.t()}
  def left_out_domains, do: @left_out

  @doc "The resources that have a feature of their own, by `{domain, resource}`."
  @spec named_resources() :: %{{atom, atom} => t | nil}
  def named_resources, do: @resources
end
