defmodule Rescord.Storage do
  @moduledoc """
  What Rescord needs from a store of files (ADR 0038): put a file, get it,
  and delete it.

  The configuration names the store, `config :rescord, :storage`:

    * `Rescord.Storage.S3` keeps the files in a bucket of a service that is
      compatible with S3: Tigris in production, and Garage on a machine for
      development;
    * `Rescord.Storage.Disk` keeps them in a directory. The tests use it,
      with a temporary directory for each test.

  A key is a path of segments. The key of each file of an organisation
  starts with the id of the organisation (`key/2`), so the files of two
  organisations never share a key. No key comes from what a person sends.
  """

  @typedoc "The key of a file in the store, for example `<organisation id>/attachments/<id>`."
  @type key :: String.t()

  @doc "Puts a file in the store under `key`, with its type."
  @callback put(key, binary, content_type :: String.t()) :: :ok | {:error, term}

  @doc "Gets the bytes of the file under `key`."
  @callback get(key) :: {:ok, binary} | {:error, :not_found | term}

  @doc "Deletes the file under `key`. A key with no file is no error."
  @callback delete(key) :: :ok | {:error, term}

  @doc "The module of the store that the configuration names."
  @spec store() :: module
  def store, do: Application.fetch_env!(:rescord, :storage)

  @doc "Puts a file in the store of the configuration."
  @spec put(key, binary, String.t()) :: :ok | {:error, term}
  def put(key, bytes, content_type), do: store().put(key, bytes, content_type)

  @doc "Gets a file from the store of the configuration."
  @spec get(key) :: {:ok, binary} | {:error, :not_found | term}
  def get(key), do: store().get(key)

  @doc "Deletes a file from the store of the configuration."
  @spec delete(key) :: :ok | {:error, term}
  def delete(key), do: store().delete(key)

  @doc """
  The key of a file of an organisation: the id of the organisation, a kind,
  and the id of the record of the file. Each part is an id or a word that
  Rescord gives, so a key has no `..` and no `/` from outside.

      iex> Rescord.Storage.key("8f0c", ["attachments", "b51e"])
      "8f0c/attachments/b51e"
  """
  @spec key(String.t(), [String.t()]) :: key
  def key(organisation_id, parts) when is_binary(organisation_id) and is_list(parts) do
    segments = [organisation_id | parts]

    if Enum.all?(segments, &segment?/1),
      do: Enum.join(segments, "/"),
      else: raise(ArgumentError, "a key is made of ids and words: #{inspect(segments)}")
  end

  defp segment?(segment),
    do: is_binary(segment) and Regex.match?(~r/\A[A-Za-z0-9_-]{1,64}\z/, segment)
end
