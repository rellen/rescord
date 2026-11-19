defmodule Rescord.StorageFixtures do
  @moduledoc """
  Files for the tests of the attachments (ADR 0041): the first bytes of each
  type that Rescord takes, and a store in the temporary directory of a test.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  @doc "The bytes of a small JPEG: its first bytes are those of the type."
  def jpeg, do: <<0xFF, 0xD8, 0xFF, 0xE0>> <> String.duplicate("a", 100)

  @doc "The bytes of a small PDF."
  def pdf, do: "%PDF-1.7\n" <> String.duplicate("b", 100)

  @doc """
  Keeps the files of the test in `tmp_dir`, a directory of ExUnit's tag
  `:tmp_dir`, and puts the store back after the test.
  """
  def disk_store!(tmp_dir) do
    previous = Application.get_env(:rescord, Rescord.Storage.Disk)
    Application.put_env(:rescord, Rescord.Storage.Disk, root: tmp_dir)
    on_exit(fn -> Application.put_env(:rescord, Rescord.Storage.Disk, previous) end)
    :ok
  end
end
