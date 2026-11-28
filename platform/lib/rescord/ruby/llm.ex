defmodule Rescord.Ruby.LLM do
  @moduledoc """
  The model of a provider, with its key. This is the only module that
  decrypts a key of Ruby (ADR 0069), and the only one that writes the mark
  that `Rescord.Ruby.Provider` asks for before a decryption. A test reads
  the sources and holds that.

  The profile with the key lives in the process that asked for it, the job
  of a reply or one "Test", and nowhere between: not in the application
  environment, not in an assign of a page, and not in the arguments of a
  job.
  """

  alias Rescord.Ruby.LLM.Profile
  alias Rescord.Ruby.Provider

  @doc """
  The profile of one provider, with its key. The caller checked who asks.

  Each reason that the key cannot be read is `:key_refused`: the secret of
  the server changed, the value is not what the vault wrote, or the row
  has no key. The error is not returned and not logged.
  """
  @spec profile_of(Provider.t()) ::
          {:ok, Profile.t()} | {:error, :key_refused | [Profile.problem()]}
  def profile_of(%Provider{} = provider) do
    with {:ok, provider} <- open(provider), do: Profile.from_provider(provider)
  end

  @doc """
  The profile of the provider of an organisation, with its key, for a
  reply. The caller checked who asks.

  It gives a profile only while Ruby is on there: the settings say so, the
  server offers their provider, and its place is the one that a person of
  the organisation agreed to. Each other case is `:key_refused`, the
  reason of a server where Ruby is not set up: no request can go.
  """
  @spec profile(term) :: {:ok, Profile.t()} | {:error, :key_refused}
  def profile(tenant) do
    with %{enabled: true, provider_id: id} = settings when is_binary(id) <-
           Rescord.Ruby.settings(tenant),
         {:ok, %Provider{offered: true} = provider} <-
           Ash.get(Provider, id, authorize?: false, not_found_error?: false),
         true <- Profile.agreed?(provider, settings.agreed_destination),
         {:ok, %Profile{} = profile} <- profile_of(provider) do
      {:ok, profile}
    else
      _no_profile -> {:error, :key_refused}
    end
  end

  defp open(%Provider{} = provider) do
    case Ash.load(provider, :api_key, authorize?: false, context: %{rescord_vault: :open}) do
      # A key is a text, or nothing for a kind that takes none.
      {:ok, %{api_key: key} = provider} when is_binary(key) or is_nil(key) -> {:ok, provider}
      _other -> {:error, :key_refused}
    end
  rescue
    # A value that cannot be opened raises out of `Ash.load/3`, and not
    # always the same error: a forbidden error when the vault refuses, an
    # unknown error when the column is not what AshCloak wrote. So each
    # exception is rescued.
    _error -> {:error, :key_refused}
  end
end
