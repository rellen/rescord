defmodule Rescord.Accounts.Validations.KnownTimeZone do
  @moduledoc """
  The time zone of an organisation is a name that the time zone rules know,
  for example `Australia/Brisbane` (ADR 0026).
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :time_zone) do
      zone when is_binary(zone) ->
        if Rescord.Accounts.time_zone?(zone) do
          :ok
        else
          {:error,
           field: :time_zone,
           message: "is not a time zone that Rescord knows, such as Australia/Brisbane"}
        end

      _not_given ->
        :ok
    end
  end
end
