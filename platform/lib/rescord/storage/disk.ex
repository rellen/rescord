defmodule Rescord.Storage.Disk do
  @moduledoc """
  A store of files in a directory (ADR 0038). The tests use it: each test
  that keeps a file gives it a temporary directory of its own, so a test
  needs no service and shares no file.

  The directory is `config :rescord, Rescord.Storage.Disk, root: "..."`.
  The key is a path below it: `Rescord.Storage.key/2` makes each key, so a
  key does not leave the directory. The type of a file is not kept: the
  record of the file holds it.
  """

  @behaviour Rescord.Storage

  @impl true
  def put(key, bytes, _content_type) when is_binary(bytes) do
    path = path(key)

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, bytes)
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

  @doc "The directory of the files."
  @spec root() :: Path.t()
  def root, do: Application.fetch_env!(:rescord, __MODULE__) |> Keyword.fetch!(:root)

  defp path(key), do: Path.join(root(), Path.safe_relative(key) |> safe!(key))

  defp safe!({:ok, relative}, _key), do: relative
  defp safe!(:error, key), do: raise(ArgumentError, "the key #{inspect(key)} leaves the store")
end
