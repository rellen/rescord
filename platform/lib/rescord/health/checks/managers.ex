defmodule Rescord.Health.Checks.Managers do
  @moduledoc """
  C8 of issue 38: an organisation with active members and no active member
  whose role has the power `:members`. Nobody there can then invite,
  remove, or change the role of a member, and only a root user can put it
  right. `NotTheLastManager` guards each action that takes the power from
  a member, but it reads and then acts, so two changes at the same time
  can pass it both. An organisation with no member yet is not a fault: its
  first administrator is still to come.

  The id is that of the organisation.
  """

  use Rescord.Health.Check

  @impl true
  def name, do: :managers
  @impl true
  def scope, do: :organisation
  @impl true
  def cadence, do: :daily
  @impl true
  def title, do: "Organisations where nobody can manage the members"

  @impl true
  def explain,
    do:
      "No active member has a role with the power to manage members. A root user makes " <>
        "a member the administrator, on the page of the members of the organisation."

  @impl true
  def run(%{organisation: organisation} = context) do
    members = table(context, "members")
    roles = table(context, "roles")

    query(
      """
      select $1::uuid as id
      where exists (select 1 from #{members} where archived_at is null)
        and not exists (
          select 1 from #{members} m join #{roles} r on r.id = m.role_id
          where m.archived_at is null and r.archived_at is null and 'members' = any(r.powers))
      """,
      [Ecto.UUID.dump!(organisation.id)]
    )
    |> found(:fail)
  end
end
