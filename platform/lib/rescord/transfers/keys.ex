defmodule Rescord.Transfers.Keys do
  @moduledoc """
  The keys of a refuge and its partner card (ADR 0043).

  `of/1` returns the four keys of a refuge, and makes them the first time.
  The private keys are in the database encrypted with the secret of the
  server: `config :rescord, Rescord.Transfers.Keys, secret: ...`, which
  production reads from `RESCORD_KEY_SECRET`. A server with another secret
  cannot read the keys that it made before, so a refuge keeps that secret
  with its backups.

  ## The partner card

  `card/1` is a line of text that an administrator gives to a refuge on
  another server: the id and the name of the refuge, and its two public
  keys. The other administrator records it (`read_card/1`), and the two
  read the fingerprint to each other, by phone or in person, before the
  first file. A card holds no secret.
  """

  require Ash.Query

  alias Rescord.Transfers.{Crypto, RefugeKey}

  @prefix "RESCORD-PARTNER-1."

  @doc "The four keys of a refuge, which this function makes the first time."
  @spec of(Ash.Resource.record()) :: Crypto.keys()
  def of(organisation) do
    case read(organisation.id) do
      %RefugeKey{} = record -> open(record)
      nil -> make(organisation.id)
    end
  end

  defp read(organisation_id) do
    RefugeKey
    |> Ash.Query.filter(organisation_id == ^organisation_id)
    |> Ash.read_one!(authorize?: false)
  end

  defp make(organisation_id) do
    keys = Crypto.keys()

    RefugeKey
    |> Ash.Changeset.for_create(
      :make,
      %{
        organisation_id: organisation_id,
        sign_public: keys.sign_public,
        box_public: keys.box_public,
        sign_private: Crypto.wrap(keys.sign_private, secret()),
        box_private: Crypto.wrap(keys.box_private, secret())
      },
      authorize?: false
    )
    |> Ash.create()
    |> case do
      {:ok, _record} -> keys
      # Another request made them at the same time: its keys count.
      {:error, _error} -> open(read(organisation_id))
    end
  end

  defp open(record) do
    case unwrap(record) do
      {:ok, _secret, sign_private, box_private} ->
        %{
          sign_public: record.sign_public,
          sign_private: sign_private,
          box_public: record.box_public,
          box_private: box_private
        }

      :error ->
        raise "the keys of refuge #{record.organisation_id} do not open with the secret of this server"
    end
  end

  # The secret of today first, then the previous one while the secret of
  # the server changes (ADR 0068). Says which secret opened the keys.
  defp unwrap(record) do
    Enum.find_value(secrets(), :error, fn secret ->
      with {:ok, sign_private} <- Crypto.unwrap(record.sign_private, secret),
           {:ok, box_private} <- Crypto.unwrap(record.box_private, secret) do
        {:ok, secret, sign_private, box_private}
      else
        :error -> nil
      end
    end)
  end

  defp secret do
    :rescord |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(:secret)
  end

  defp secrets do
    previous = :rescord |> Application.fetch_env!(__MODULE__) |> Keyword.get(:previous_secret)
    [secret() | List.wrap(previous)]
  end

  @typedoc "What `count/0` and `rewrap/0` found, as numbers of refuges."
  @type report :: %{current: non_neg_integer, previous: non_neg_integer, sealed: non_neg_integer}

  @doc """
  Counts the refuges by the secret that opens their keys: the secret of
  today, the previous secret, or none. It changes nothing.
  """
  @spec count() :: report
  def count, do: visit(false)

  @doc """
  Encrypts again, with the secret of today, the keys that the previous
  secret of the server encrypted, and returns the counts as they were
  before (ADR 0068). `bin/rotate-vault` runs it. A second run changes
  nothing.
  """
  @spec rewrap() :: report
  def rewrap, do: visit(true)

  defp visit(write?) do
    current = secret()

    RefugeKey
    |> Ash.read!(authorize?: false)
    |> Enum.reduce(%{current: 0, previous: 0, sealed: 0}, fn record, report ->
      case unwrap(record) do
        {:ok, ^current, _sign_private, _box_private} ->
          Map.update!(report, :current, &(&1 + 1))

        {:ok, _previous, sign_private, box_private} ->
          if write? do
            record
            |> Ash.Changeset.for_update(
              :rewrap,
              %{
                sign_private: Crypto.wrap(sign_private, current),
                box_private: Crypto.wrap(box_private, current)
              },
              authorize?: false
            )
            |> Ash.update!()
          end

          Map.update!(report, :previous, &(&1 + 1))

        :error ->
          Map.update!(report, :sealed, &(&1 + 1))
      end
    end)
  end

  @doc "The partner card of a refuge: one line of text, with no secret in it."
  @spec card(Ash.Resource.record()) :: String.t()
  def card(organisation) do
    keys = of(organisation)

    @prefix <>
      Base.url_encode64(
        Jason.encode!(%{
          "refuge" => organisation.id,
          "name" => organisation.name,
          "sign_key" => Base.encode64(keys.sign_public),
          "box_key" => Base.encode64(keys.box_public)
        }),
        padding: false
      )
  end

  @doc "The fingerprint of the keys of a refuge."
  @spec fingerprint(Ash.Resource.record()) :: String.t()
  def fingerprint(organisation) do
    keys = of(organisation)
    Crypto.fingerprint(keys.sign_public, keys.box_public)
  end

  @doc """
  The facts of a partner card: the id and the name of the refuge, and its
  two public keys. Returns `:error` for text that is not a card.
  """
  @spec read_card(term) ::
          {:ok,
           %{refuge_id: String.t(), name: String.t(), sign_public: binary, box_public: binary}}
          | :error
  def read_card(text) when is_binary(text) do
    with @prefix <> encoded <- String.trim(text),
         {:ok, json} <- Base.url_decode64(encoded, padding: false),
         {:ok, %{"refuge" => refuge, "name" => name, "sign_key" => sign, "box_key" => box}} <-
           Jason.decode(json),
         {:ok, refuge_id} <- Ecto.UUID.cast(refuge),
         true <- is_binary(name) and String.length(name) in 1..100,
         {:ok, <<_::binary-size(32)>> = sign_public} <- Base.decode64(sign),
         {:ok, <<_::binary-size(32)>> = box_public} <- Base.decode64(box) do
      {:ok, %{refuge_id: refuge_id, name: name, sign_public: sign_public, box_public: box_public}}
    else
      _not_a_card -> :error
    end
  end

  def read_card(_other), do: :error
end
