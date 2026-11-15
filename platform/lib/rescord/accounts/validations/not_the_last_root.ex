defmodule Rescord.Accounts.Validations.NotTheLastRoot do
  @moduledoc """
  Refuses to make the last root user an ordinary user.

  Without a root user nobody can create an organisation or make another root
  user, and `Rescord.Accounts.bootstrap_root/1` is the only way back.
  """

  use Ash.Resource.Validation

  require Ash.Query

  @impl true
  def validate(changeset, _opts, _context) do
    others =
      Rescord.Accounts.User
      |> Ash.Query.for_read(:roots)
      |> Ash.Query.filter(id != ^changeset.data.id)
      |> Ash.exists?(authorize?: false)

    if others do
      :ok
    else
      {:error, field: :root?, message: "is the last root user, and stays one"}
    end
  end
end
