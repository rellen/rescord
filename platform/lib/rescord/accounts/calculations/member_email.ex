defmodule Rescord.Accounts.Calculations.MemberEmail do
  @moduledoc """
  The email address of the user of each member.

  A user reads only their own record. A person who can read a member can see
  whose it is, so this calculation reads the users with no policy. It is the
  one way from a member to the address of another user.
  """

  use Ash.Resource.Calculation

  require Ash.Query

  @impl true
  def load(_query, _opts, _context), do: [:user_id]

  @impl true
  def calculate(members, _opts, _context) do
    ids = Enum.map(members, & &1.user_id)

    emails =
      Rescord.Accounts.User
      |> Ash.Query.filter(id in ^ids)
      |> Ash.Query.select([:id, :email])
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.id, &1.email})

    {:ok, Enum.map(members, &Map.get(emails, &1.user_id))}
  end
end
