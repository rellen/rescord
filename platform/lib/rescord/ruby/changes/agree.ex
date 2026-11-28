defmodule Rescord.Ruby.Changes.Agree do
  @moduledoc """
  Holds the settings of an organisation to the providers of the server,
  and writes the agreement to the place of the records (ADR 0069).

    * A provider that the settings choose is one that the server offers.
      Settings that keep their provider and have Ruby off are not held to
      it: an administrator turns Ruby off, and sets the allowance, also
      after the root user took the provider away.
    * With Ruby on, the provider is there and ready, and the argument
      `agreed_to` is the key of its place as it is now. The page gives the
      key of the place that it showed, so an administrator never agrees to
      a place that they did not read.
    * The agreement is written when Ruby goes on, and when the place is
      another one than the last agreement: the key, the sentence and the
      time.
    * The allowance starts at the default of the provider.

  It reads the provider through Ash, and decrypts no key.
  """

  use Ash.Resource.Change

  alias Rescord.Ruby.LLM.Profile
  alias Rescord.Ruby.Provider

  # The change reads the provider, which is not temporal, and takes the
  # instant of the action for the time of the agreement.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, _opts, _context) do
    enabled? = Ash.Changeset.get_attribute(changeset, :enabled) == true
    provider_id = Ash.Changeset.get_attribute(changeset, :provider_id)
    provider = provider_id && provider(provider_id)

    cond do
      not enabled? and not Ash.Changeset.changing_attribute?(changeset, :provider_id) ->
        allowance(changeset, provider)

      provider_id && not offered?(provider) ->
        refuse(changeset, :provider_id, "choose a service that this server offers")

      not enabled? ->
        allowance(changeset, provider)

      is_nil(provider) ->
        refuse(changeset, :provider_id, "choose the service first")

      Ash.Changeset.get_argument(changeset, :agreed_to) != Profile.place_key(provider) ->
        refuse(
          changeset,
          :agreed_to,
          "the place of the records is another one now: read it, and then turn Ruby on"
        )

      true ->
        changeset |> allowance(provider) |> agree(provider)
    end
  end

  defp provider(id) do
    case Ash.get(Provider, id, authorize?: false, not_found_error?: false) do
      {:ok, %Provider{} = provider} -> provider
      _none -> nil
    end
  end

  # A provider that a request can use: offered, complete, and with a place.
  defp offered?(%Provider{offered: true} = provider),
    do: Profile.problems(provider) == [] and is_binary(Profile.place_key(provider))

  defp offered?(_other), do: false

  defp allowance(changeset, %Provider{default_allowance: default}) do
    if is_nil(Ash.Changeset.get_attribute(changeset, :allowance)),
      do: Ash.Changeset.force_change_attribute(changeset, :allowance, default),
      else: changeset
  end

  defp allowance(changeset, _no_provider), do: changeset

  defp agree(changeset, provider) do
    key = Profile.place_key(provider)
    was_on? = changeset.action_type == :update and changeset.data.enabled == true

    if was_on? and changeset.data.agreed_destination == key do
      changeset
    else
      changeset
      |> Ash.Changeset.force_change_attribute(:agreed_destination, key)
      |> Ash.Changeset.force_change_attribute(:agreed_words, Profile.place(provider))
      |> Ash.Changeset.force_change_attribute(:agreed_at, instant(changeset))
    end
  end

  defp refuse(changeset, field, message),
    do: Ash.Changeset.add_error(changeset, field: field, message: message)

  defp instant(%{as_of: %DateTime{} = instant}), do: instant
  defp instant(_changeset), do: DateTime.utc_now()
end
