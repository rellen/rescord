defmodule Rescord.Calendars.Validations.HasAPart do
  @moduledoc """
  A feed holds one part at least: tasks, the days that residents are
  expected back, or the expiry dates of the stock. A feed with no part is
  an empty calendar.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    parts? =
      Ash.Changeset.get_attribute(changeset, :tasks) != :none or
        Ash.Changeset.get_attribute(changeset, :with_returns) == true or
        Ash.Changeset.get_attribute(changeset, :with_expiry) == true

    if parts? do
      :ok
    else
      {:error, field: :tasks, message: "or another part is necessary: the feed would be empty"}
    end
  end
end
