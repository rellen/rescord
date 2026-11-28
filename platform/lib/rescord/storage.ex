defmodule Rescord.Storage do
  @moduledoc """
  What Rescord needs from a store of files (ADR 0038): put a file, get it,
  delete it, and list the files.

  The configuration names the store, `config :rescord, :storage`:

    * `Rescord.Storage.S3` keeps the files in a bucket of a service that is
      compatible with S3: Tigris in production, and Garage on a machine for
      development;
    * `Rescord.Storage.Disk` keeps them in a directory. The tests use it,
      with a temporary directory for each test.

  A key is a path of segments. The key of each file of an organisation
  starts with the id of the organisation (`key/2`), so the files of two
  organisations never share a key. No key comes from what a person sends.

  Rescord never changes a file: a key gets its bytes one time. So
  `Rescord.Storage.Move` can copy the files of one store into another
  while Rescord runs (ADR 0059).
  """

  @typedoc "The key of a file in the store, for example `<organisation id>/attachments/<id>`."
  @type key :: String.t()

  @doc "Puts a file in the store under `key`, with its type."
  @callback put(key, binary, content_type :: String.t()) :: :ok | {:error, term}

  @doc "Gets the bytes of the file under `key`."
  @callback get(key) :: {:ok, binary} | {:error, :not_found | term}

  @doc "Deletes the file under `key`. A key with no file is no error."
  @callback delete(key) :: :ok | {:error, term}

  @doc """
  Lists the name of each file in the store. A store can hold a file that
  Rescord did not put there, so a name is a key only when `key?/1` says so.
  """
  @callback list() :: {:ok, [String.t()]} | {:error, term}

  @doc """
  Lists each file in the store with its size in bytes, as `{name, size}`.
  The store gives the size with its list, and reads no file for it. The
  names are those of `list/0`.
  """
  @callback files() :: {:ok, [{String.t(), non_neg_integer}]} | {:error, term}

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

  @doc "Lists each file of the store of the configuration, with its size in bytes."
  @spec files() :: {:ok, [{String.t(), non_neg_integer}]} | {:error, term}
  def files, do: store().files()

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

  @doc """
  Whether `name` has the shape of a key that `key/2` makes: two segments or
  more, each an id or a word.

      iex> Rescord.Storage.key?("8f0c/attachments/b51e")
      true
      iex> Rescord.Storage.key?("lost+found")
      false
      iex> Rescord.Storage.key?("8f0c/photos/b51e.part-1a2b")
      false
  """
  @spec key?(String.t()) :: boolean
  def key?(name) when is_binary(name) do
    case String.split(name, "/") do
      [_one] -> false
      segments -> Enum.all?(segments, &segment?/1)
    end
  end

  @doc """
  Whether `segment` can be a part of a key: 1 to 64 letters, digits, `_`
  and `-`.
  """
  @spec segment?(term) :: boolean
  def segment?(segment),
    do: is_binary(segment) and Regex.match?(~r/\A[A-Za-z0-9_-]{1,64}\z/, segment)

  @doc """
  The store `store` in words, from its settings: a directory, or a bucket
  at its address. The words name no key and no secret.
  """
  @spec describe(module) :: String.t()
  def describe(store) do
    config = Application.get_env(:rescord, store, [])

    cond do
      config[:root] -> "the directory #{config[:root]}"
      config[:bucket] -> "the bucket #{config[:bucket]} at #{config[:endpoint]}"
      true -> inspect(store)
    end
  end

  @doc """
  A size in words, for a report of a command.

      iex> Rescord.Storage.size_words(512)
      "512 B"
      iex> Rescord.Storage.size_words(2_540_000)
      "2.5 MB"
  """
  @spec size_words(non_neg_integer) :: String.t()
  def size_words(bytes) when bytes < 1_000, do: "#{bytes} B"
  def size_words(bytes) when bytes < 1_000_000, do: "#{Float.round(bytes / 1_000, 1)} kB"

  def size_words(bytes) when bytes < 1_000_000_000,
    do: "#{Float.round(bytes / 1_000_000, 1)} MB"

  def size_words(bytes), do: "#{Float.round(bytes / 1_000_000_000, 2)} GB"

  @doc """
  Why a store did not do what Rescord asked, in words, for a report of a
  command: the status of a service, or the fault of a file or a directory
  as `Rescord.Storage.Disk` gives it.
  """
  @spec reason_words(term) :: String.t()
  def reason_words({:status, status}), do: "the service answered #{status}"
  def reason_words(:not_found), do: "it is not there"
  def reason_words(:bad_listing), do: "the service gave a list that Rescord cannot read"

  def reason_words({reason, path}) when is_atom(reason) and is_binary(path),
    do: "#{posix_words(reason)}: #{path}"

  def reason_words(reason) when is_atom(reason), do: posix_words(reason)
  def reason_words(reason) when is_exception(reason), do: Exception.message(reason)
  def reason_words(reason), do: inspect(reason)

  defp posix_words(reason) do
    case to_string(:file.format_error(reason)) do
      "unknown POSIX error" <> _rest -> inspect(reason)
      words -> words
    end
  end
end
