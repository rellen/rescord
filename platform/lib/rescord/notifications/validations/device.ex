defmodule Rescord.Notifications.Validations.Device do
  @moduledoc """
  A subscription that a browser sent has the form of one: an address at a
  push service of a browser, a public key of P-256, and a secret of 16
  bytes. Rescord sends a request to the address, so it takes no other.
  """

  use Ash.Resource.Validation

  alias Rescord.Notifications.WebPush

  @impl true
  def validate(changeset, _opts, _context) do
    endpoint = Ash.Changeset.get_attribute(changeset, :endpoint)
    key = Ash.Changeset.get_attribute(changeset, :device_key)
    auth = Ash.Changeset.get_argument_or_attribute(changeset, :auth)

    cond do
      not WebPush.allowed_endpoint?(endpoint) ->
        {:error, field: :endpoint, message: "is not the address of a push service of a browser"}

      not match?({:ok, <<4, _::binary-size(64)>>}, WebPush.decode(key)) ->
        {:error, field: :device_key, message: "is not a key of a device"}

      not match?({:ok, <<_::binary-size(16)>>}, WebPush.decode(auth)) ->
        {:error, field: :auth, message: "is not a secret of a device"}

      true ->
        :ok
    end
  end
end
