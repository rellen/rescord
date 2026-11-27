defmodule Rescord.Release do
  @moduledoc """
  The tasks of a release, which has no Mix (ADR 0044). An operator runs
  each with `bin/rescord eval`:

      bin/rescord eval "Rescord.Release.migrate()"
      bin/rescord eval 'Rescord.Release.bootstrap_root("you@example.org")'

  `migrate/0` runs the migrations of the database and then the migrations
  of the schema of each organisation (ADR 0011), as `mix ash.migrate` does
  on a machine for development. The Docker image, the NixOS module and the
  systemd unit of the tarball run it before each start, so an upgrade
  migrates by itself. A migration that has run does not run again.

  A setting that is missing or wrong stops each of these, and the server,
  before it does anything: `config/runtime.exs` reads each one
  (`docs/self-hosting.md` lists them).

  `check/1` checks that the server is ready before it goes live
  (`Rescord.Release.Check`, ADR 0049). `bin/check` runs it.

  `bootstrap_root/1` makes the first root user (`docs/domain.md`, section
  5.1). It does nothing when a root user exists.

  `move_storage/2` copies the files of one store into the other, for a
  server that changes its store (`Rescord.Storage.Move`, ADR 0059).
  `bin/move-storage` runs it.
  """

  use Boundary, top_level?: true, deps: [Rescord, Rescord.Accounts]

  alias Rescord.Storage.Move

  @app :rescord

  @doc "Runs each migration of the database, then each tenant migration of each organisation."
  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))

      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          path = Ecto.Migrator.migrations_path(repo, "tenant_migrations")

          for tenant <- repo.all_tenants() do
            Ecto.Migrator.run(repo, path, :up, all: true, prefix: tenant)
          end
        end)
    end

    :ok
  end

  @doc "Takes the migrations of the database back to the version `version`."
  @spec rollback(module, integer) :: :ok
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
    :ok
  end

  @doc """
  Makes the first root user for the address `address`, and prints what
  happened. The person then asks for a sign-in link on the sign-in page.
  """
  @spec bootstrap_root(String.t()) :: :ok | {:error, term}
  def bootstrap_root(address) when is_binary(address) do
    start_app()

    case Rescord.Accounts.bootstrap_root(address) do
      {:ok, user} ->
        IO.puts(
          "#{user.email} is the first root user. Ask for a sign-in link on the sign-in page."
        )

        :ok

      {:error, :root_exists} ->
        IO.puts("Rescord has a root user already. A root user makes another one.")
        {:error, :root_exists}

      {:error, error} ->
        IO.puts("The root user was not made: #{Exception.message(error)}")
        {:error, error}
    end
  end

  @doc """
  Checks the database, the migrations, the store and the SMTP server, and
  with an address sends a test email to it. Prints the version of Rescord
  (ADR 0060), and then a line for each check.
  """
  @spec check(String.t() | nil) :: :ok | :error
  def check(address \\ nil) do
    load_app()
    IO.puts("Rescord #{Rescord.version()}\n")
    results = Rescord.Release.Check.run(address)
    IO.puts(Rescord.Release.Check.format(results))

    if Rescord.Release.Check.passed?(results) do
      IO.puts("\nRescord is ready.")
      :ok
    else
      IO.puts("\nFix each FAIL, and run bin/check again.")
      :error
    end
  end

  @doc """
  Copies each file of the store `from` into the store `to`, each `"disk"`
  or `"s3"`, checks each copy, and prints what happened. It deletes
  nothing, and a second run copies only what is missing (ADR 0059).

  It needs the settings of both stores. `bin/move-storage` sets
  `RESCORD_BOTH_STORES`, so that `config/runtime.exs` reads both.
  """
  @spec move_storage(String.t(), String.t()) :: :ok | :error
  def move_storage(from, to) do
    load_app()
    {:ok, _apps} = Application.ensure_all_started(:req)

    case {store(from), store(to)} do
      {{:ok, from}, {:ok, to}} when from != to ->
        move(from, to)

      _refused ->
        IO.puts("Give the store of the files and the store to copy them to: disk s3, or s3 disk.")
        :error
    end
  end

  defp store("disk"), do: {:ok, Rescord.Storage.Disk}
  defp store("s3"), do: {:ok, Rescord.Storage.S3}
  defp store(_other), do: :error

  defp move(from, to) do
    progress = fn report ->
      if line = Move.progress_line(report, from, to), do: IO.puts(line)
    end

    case Move.run(from, to, progress: progress) do
      {:ok, report} ->
        IO.puts(Move.format(report, from, to))
        if Move.complete?(report), do: :ok, else: :error

      {:error, fault} ->
        IO.puts(Move.format_fault(fault, from, to))
        :error
    end
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    # Many platforms need SSL when they connect to the database.
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end

  defp start_app do
    load_app()
    {:ok, _apps} = Application.ensure_all_started(@app)
  end
end
