defmodule Rescord.Notifications.Grants do
  @moduledoc """
  What a role can do with the notifications of an organisation (ADR 0024
  and issue 29): each role reads its own notifications and marks them as
  read, and reads and sets its own preferences. No power changes that: a
  notification is of one person.

  The devices and the topics of ntfy are of a user, outside an
  organisation, and their policies are the person. The settings are a root
  user's.
  """

  @behaviour Rescord.Accounts.Grants

  import Ash.Expr, only: [expr: 1, actor: 1]

  alias Rescord.Notifications.{Notification, Preference}

  @impl true
  def reads do
    [
      {Notification, :read, :own},
      {Notification, :mine, :own},
      {Notification, :mark_read, :own},
      {Preference, :read, :own},
      {Preference, :set, :all}
    ]
  end

  @impl true
  def powers, do: %{}

  @impl true
  def filter(Notification, :own), do: expr(user_id == ^actor(:id))
  def filter(Preference, :own), do: expr(user_id == ^actor(:id))
  def filter(_resource, _scope), do: nil
end
