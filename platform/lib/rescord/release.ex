defmodule Rescord.Release do
  @moduledoc """
  The tasks of a release, which has no Mix (ADR 0044). An operator runs
  each with a script of `bin`, or with `bin/rescord eval`:

      bin/migrate
      bin/rescord eval 'Rescord.Release.bootstrap_root("you@example.org")'

  `migrate/1` runs the migrations of the database and then the migrations
  of the schema of each organisation (ADR 0011). The Docker image, the
  NixOS module and the systemd unit of the tarball run it before each
  start, so an upgrade migrates by itself. A migration that has run does
  not run again.

  Before it changes anything, `migrate/1` rehearses the upgrade
  (`Rescord.Release.Rehearsal`, ADR 0081): each migration runs in a
  transaction that is taken back. When one fails there, `migrate/1`
  changes nothing, says which and where, and the server does not start.
  `rehearse/0` is the rehearsal alone.

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

  `check_files/1` compares the files of the store with the records of the
  database, and changes nothing (`Rescord.Storage.Compare`, ADR 0091).
  `bin/check-files` runs it.

  `rotate_vault/0` encrypts again, with the secret of today, what the
  previous secret of the server encrypted (ADR 0068). `bin/rotate-vault`
  runs it.
  """

  use Boundary,
    top_level?: true,
    deps: [
      Rescord,
      Rescord.Accounts,
      Rescord.Expenses,
      Rescord.Journal,
      Rescord.Mail,
      Rescord.Photos,
      Rescord.Ruby,
      Rescord.Transfers,
      Rescord.Vault
    ]

  alias Rescord.Release.Rehearsal
  alias Rescord.Storage.{Compare, Move}

  @app :rescord

  @doc """
  Rehearses the upgrade, and then runs each migration of the database and
  each tenant migration of each organisation. `:error` when the rehearsal
  fails: then nothing is changed.

  `rehearse: false` leaves the rehearsal out, for a migration that the
  upgrade notes of its release say cannot be rehearsed.
  """
  @spec migrate(keyword) :: :ok | :error
  def migrate(opts \\ []) do
    load_app()

    if Keyword.get(opts, :rehearse, true) do
      case rehearsal() do
        {:nothing, _plan} ->
          run_migrations()

        {:passed, _plan} = result ->
          IO.puts(Rehearsal.format(result) <> " Rescord runs the migrations now.")
          run_migrations()

        {:failed, _plan, _faults} = result ->
          IO.puts(Rehearsal.format(result))
          :error
      end
    else
      IO.puts("Rescord runs the migrations with no rehearsal.")
      run_migrations()
    end
  end

  @doc """
  Rehearses the upgrade, prints what it found, and changes nothing
  (ADR 0081). `bin/migrate --rehearse` runs it.
  """
  @spec rehearse() :: :ok | :error
  def rehearse do
    load_app()
    result = rehearsal()
    IO.puts(Rehearsal.format(result))
    if match?({:failed, _plan, _faults}, result), do: :error, else: :ok
  end

  defp rehearsal do
    {:ok, result, _apps} = Ecto.Migrator.with_repo(Rescord.Repo, fn _repo -> Rehearsal.run() end)
    result
  end

  defp run_migrations do
    # Ecto compiles the file of a tenant migration one time for each
    # organisation, and the compiler would warn each time after the first.
    conflicts = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
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
    after
      Code.put_compiler_option(:ignore_module_conflict, conflicts)
    end
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

  @doc """
  Compares the files of the store with the records of the database, and
  prints the report (ADR 0091): the files that a record names, the
  leftovers that no record names, with their size, and each file that a
  record names and that the store does not have. `all: true` prints each
  file of a group, and not the first 20.

  It changes nothing in the store and nothing in the database. The result
  is `:ok` when the store has each file that a record names, with
  leftovers or with none, `:missing` when it does not, and `:error` when
  the comparison could not be made.
  """
  @spec check_files(keyword) :: :ok | :missing | :error
  def check_files(opts \\ []) do
    load_app()
    {:ok, _apps} = Application.ensure_all_started(:req)
    start_repo()
    store = Rescord.Storage.store()

    case Rescord.Release.Files.compare() do
      {:ok, report} ->
        IO.puts(Compare.format(report, store, opts))
        if Compare.complete?(report), do: :ok, else: :missing

      {:error, fault} ->
        IO.puts(Compare.format_fault(fault, store))
        :error
    end
  end

  @doc """
  Encrypts again, with the secret of today, each value that the previous
  secret of the server encrypted: the secrets of the settings in
  `Rescord.Vault`, and the private keys of the transfers (ADR 0068). It
  prints the counts, and no value.

  A change of `RESCORD_KEY_SECRET` has three steps: start Rescord with the
  new secret and with the old one as `RESCORD_KEY_SECRET_PREVIOUS`, run
  this, and take the second setting out. A second run changes nothing. A
  value that neither secret opens stays as it is, and the result is
  `:error`.
  """
  @spec rotate_vault() :: :ok | :error
  def rotate_vault do
    load_app()
    start_repo()

    values = Rescord.Vault.rotate()
    keys = Rescord.Transfers.rewrap_keys()

    IO.puts(rotated("The secrets of the settings", values))
    IO.puts(rotated("The keys of the transfers", keys))

    cond do
      values.sealed + keys.sealed > 0 ->
        IO.puts(
          "\nSome values open with neither secret, and stay as they are. " <>
            "Give the secret that encrypted them as RESCORD_KEY_SECRET_PREVIOUS, and run this again."
        )

        :error

      is_binary(Application.fetch_env!(@app, Rescord.Vault)[:previous_secret]) ->
        IO.puts("\nTake RESCORD_KEY_SECRET_PREVIOUS out now, and start Rescord again.")
        :ok

      true ->
        IO.puts("\nRESCORD_KEY_SECRET_PREVIOUS is not set: there was nothing to encrypt again.")
        :ok
    end
  end

  defp rotated(name, report) do
    "#{name}: #{report.previous} encrypted again, " <>
      "#{report.current} had the secret of today, #{report.sealed} open with neither secret."
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

  # The repository with a small pool, and not the application: its jobs
  # would run.
  defp start_repo do
    for app <- [:ecto_sql, :postgrex, :ash] do
      {:ok, _apps} = Application.ensure_all_started(app)
    end

    case Rescord.Repo.start_link(pool_size: 2) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  defp start_app do
    load_app()
    {:ok, _apps} = Application.ensure_all_started(@app)
  end
end
