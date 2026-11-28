defmodule Rescord.Release.Files do
  @moduledoc """
  Reads the store and the database for the comparison of the two
  (`Rescord.Storage.Compare`, ADR 0091). `Rescord.Release.check_files/1`
  runs it and prints the report, and `bin/check-files` runs that.

  It lists the store one time, and then reads the keys that the records
  name: each domain of `domains/0` gives the keys of its records in the
  schema of each organisation, with `file_keys/1`
  (`Rescord.Storage.Named`). The store comes first, so a file of an upload
  that ends between the two is named, and is no leftover. Such a file is
  not in the list: the store is asked for each file that the list does not
  have, before the report calls it missing.

  It reads with no actor, as `Rescord.Vault` does, and it changes nothing
  in the store and nothing in the database. It needs the repository and
  not the application, so an operator can run it beside a server that
  works.
  """

  alias Rescord.Release.Check
  alias Rescord.{Repo, Storage}
  alias Rescord.Storage.Compare

  @domains [Rescord.Journal, Rescord.Photos, Rescord.Expenses, Rescord.Transfers]

  @typedoc """
  Why the comparison could not be made: the store did not list its files,
  the database did not answer, or migrations of this version have not run.
  """
  @type fault :: {:list, term} | {:database, String.t()} | {:migrations, String.t()}

  @doc """
  The domains that keep files. Each one has `file_keys/1`. A test holds
  that no resource with a key of a file is outside them
  (`Rescord.Release.FilesTest`).
  """
  @spec domains() :: [module]
  def domains, do: @domains

  @doc """
  Compares the store of the configuration with the database, and returns
  the report.
  """
  @spec compare() :: {:ok, Compare.t()} | {:error, fault}
  def compare do
    store = Storage.store()

    with :ok <- migrated(),
         {:ok, files} <- list(store),
         {:ok, named} <- named() do
      {:ok, files |> Compare.run(named) |> Compare.confirm(&store.get/1)}
    end
  end

  # A table of this version is not there before its migration.
  defp migrated do
    case Check.migrations() do
      {:ok, _name, _words} ->
        :ok

      {:note, _name, words} ->
        {:error, {:migrations, words}}

      {:fail, _name, words} ->
        {:error, {:database, String.replace_prefix(words, "cannot read: ", "")}}
    end
  end

  defp list(store) do
    case store.files() do
      {:ok, files} -> {:ok, files}
      {:error, reason} -> {:error, {:list, reason}}
    end
  end

  # For the id of each organisation, the keys that its records name.
  defp named do
    named =
      for "org_" <> organisation_id <- Repo.all_tenants(), into: %{} do
        {organisation_id, Enum.flat_map(@domains, & &1.file_keys(organisation_id))}
      end

    {:ok, named}
  rescue
    error -> {:error, {:database, Exception.message(error)}}
  end
end
