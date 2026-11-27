defmodule Rescord.Storage.Disk do
  @moduledoc """
  A store of files in a directory (ADR 0038). The tests use it: each test
  that keeps a file gives it a temporary directory of its own, so a test
  needs no service and shares no file.

  The directory is `config :rescord, Rescord.Storage.Disk, root: "..."`.
  The key is a path below it: `Rescord.Storage.key/2` makes each key, so a
  key does not leave the directory. The type of a file is not kept: the
  record of the file holds it.

  A file has its key as its path only when each byte is written: `put/3`
  writes beside it, under a name that is no key, and then gives it its
  name. A put that stops in the middle leaves no half of a file under a
  key (ADR 0059).
  """

  @behaviour Rescord.Storage

  alias Rescord.Storage

  @impl true
  def put(key, bytes, _content_type) when is_binary(bytes) do
    path = path(key)
    # A dot is in no key, so `list/0` never gives this name as a key.
    part = path <> ".part-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(part, bytes, [:sync]),
         :ok <- File.rename(part, path) do
      :ok
    else
      {:error, reason} ->
        File.rm(part)
        {:error, reason}
    end
  end

  @impl true
  def get(key) do
    case File.read(path(key)) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete(key) do
    case File.rm(path(key)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists each file below the directory, by its path from there. It does not
  open a directory whose name can be no part of a key, such as the
  `lost+found` of a volume: it gives that name, as it gives the name of a
  file. A directory that it cannot read is an error,
  `{:error, {reason, path}}`.
  """
  @impl true
  def list do
    with {:ok, names} <- walk(root(), "", []), do: {:ok, Enum.sort(names)}
  end

  defp walk(directory, prefix, found) do
    case File.ls(directory) do
      {:ok, entries} ->
        Enum.reduce_while(entries, {:ok, found}, fn entry, {:ok, found} ->
          path = Path.join(directory, entry)

          if Storage.segment?(entry) and directory?(path) do
            case walk(path, prefix <> entry <> "/", found) do
              {:ok, found} -> {:cont, {:ok, found}}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          else
            {:cont, {:ok, [prefix <> entry | found]}}
          end
        end)

      {:error, reason} ->
        {:error, {reason, directory}}
    end
  end

  # A link to a directory is not a directory of the store.
  defp directory?(path), do: match?({:ok, %File.Stat{type: :directory}}, File.lstat(path))

  @doc "The directory of the files."
  @spec root() :: Path.t()
  def root, do: Application.fetch_env!(:rescord, __MODULE__) |> Keyword.fetch!(:root)

  defp path(key), do: Path.join(root(), Path.safe_relative(key) |> safe!(key))

  defp safe!({:ok, relative}, _key), do: relative
  defp safe!(:error, key), do: raise(ArgumentError, "the key #{inspect(key)} leaves the store")
end
