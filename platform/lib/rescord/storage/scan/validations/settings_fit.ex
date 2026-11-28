defmodule Rescord.Storage.Scan.Validations.SettingsFit do
  @moduledoc """
  The settings of the scan make sense together: an address is `host:port`
  or the absolute path of a Unix socket (`Rescord.Storage.Scan.Clamd.parse/1`),
  and the scan is on only with an address.
  """

  use Ash.Resource.Validation

  alias Rescord.Storage.Scan.Clamd

  @impl true
  def validate(changeset, _opts, _context) do
    address = Ash.Changeset.get_attribute(changeset, :address)

    cond do
      address not in [nil, ""] and Clamd.parse(address) == :error ->
        {:error,
         field: :address,
         message: "give host:port, such as clamd:3310, or the path of a socket that starts with /"}

      Ash.Changeset.get_attribute(changeset, :scan_on) and address in [nil, ""] ->
        {:error, field: :address, message: "give the address of clamd"}

      true ->
        :ok
    end
  end
end
