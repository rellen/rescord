defmodule Rescord.Notifications.Validations.SettingsFit do
  @moduledoc """
  The settings of the channels make sense together: Web Push is on only
  with keys and a contact of `mailto:` or `https://`, and ntfy is on only
  with the address of a server over HTTPS.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    get = &Ash.Changeset.get_attribute(changeset, &1)

    cond do
      get.(:contact) not in [nil, ""] and not contact?(get.(:contact)) ->
        {:error, field: :contact, message: "start the address with mailto: or https://"}

      get.(:push_on) and is_nil(get.(:vapid_public_key)) ->
        {:error, field: :push_on, message: "make the keys first"}

      get.(:push_on) and get.(:contact) in [nil, ""] ->
        {:error, field: :contact, message: "give an address for the push services"}

      get.(:ntfy_url) not in [nil, ""] and not https?(get.(:ntfy_url)) ->
        {:error, field: :ntfy_url, message: "give an address that starts with https://"}

      get.(:ntfy_on) and get.(:ntfy_url) in [nil, ""] ->
        {:error, field: :ntfy_url, message: "give the address of the server of ntfy"}

      true ->
        :ok
    end
  end

  defp contact?("mailto:" <> address), do: String.contains?(address, "@")
  defp contact?(other), do: https?(other)

  defp https?(text) do
    case URI.new(text) do
      {:ok, %URI{scheme: "https", host: host, userinfo: nil}} when host not in [nil, ""] -> true
      _other -> false
    end
  end
end
