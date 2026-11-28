defmodule Rescord.Calendars.Grants do
  @moduledoc """
  What a role can do with the calendar feeds of an organisation (ADR 0024
  and ADR 0074).

  The power `:calendar` makes a feed, and reads and revokes the feeds of
  the person: the scope `own`. A feed copies data of the organisation to a
  calendar service that the organisation does not run, so it is a power,
  and not a thing that each role can do.

  The power `:members` reads and revokes the feed of each member: a person
  who invites and removes the members sees who has a feed. That person
  reads no address: Rescord stores none.

  No role has a grant for `mark`: Rescord runs it when a calendar app reads
  a feed.
  """

  @behaviour Rescord.Accounts.Grants

  import Ash.Expr, only: [expr: 1, actor: 1]

  alias Rescord.Calendars.Feed

  @impl true
  def reads, do: []

  @impl true
  def powers do
    %{
      calendar: [{Feed, :subscribe, :all}, {Feed, :read, :own}, {Feed, :revoke, :own}],
      members: [{Feed, :read, :all}, {Feed, :revoke, :all}]
    }
  end

  @impl true
  def filter(Feed, :own), do: expr(owner_id == ^actor(:id))
  def filter(_resource, _scope), do: nil
end
