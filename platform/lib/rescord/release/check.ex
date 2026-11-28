defmodule Rescord.Release.Check do
  @moduledoc """
  Checks that a server is ready, before it goes live (ADR 0049):

    * the database answers, and is PostgreSQL 18 or later;
    * the migrations that have not run, which the next start runs;
    * the store takes a file, gives it back, and deletes it;
    * the SMTP server takes the connection and the user, with the TLS of
      the settings, and sends nothing;
    * the values that the secret of the server encrypts open with it
      (ADR 0068);
    * each provider of the assistant has what a request needs (ADR 0069).
      This check reads the database, sends no request and decrypts no key;
    * what the server does with its usage counts, and what the last send
      found (ADR 0098). It sends nothing;
    * with an address, a short email reaches that address.

  `Rescord.Release.check/1` runs the checks and prints them, and
  `bin/check` runs that. A check reads the settings of the server, and no
  line names a password or a key.

  `run/1` starts only what the checks need, and not the application: the
  jobs of the application would run, and a wrong setting would stop the
  start before a check could name it.
  """

  alias Rescord.{Mailer, Repo, Ruby, Storage, Transfers, Usage, Vault}

  @typedoc """
  The result of a check: `:ok`, `:note` for something to know that is not a
  fault, or `:fail`, with the words that say what the check found.
  """
  @type result :: {:ok | :note | :fail, name :: String.t(), words :: String.t()}

  @postgres_minimum 180_000

  @doc """
  Runs each check, and returns the results in order. `address`, when it is
  given, receives a test email.
  """
  @spec run(String.t() | nil) :: [result]
  def run(address \\ nil) do
    start()

    migrations = migrations()

    # The checks that read tables wait for the migrations of a new version:
    # the next start runs them.
    of_the_database =
      if match?({:ok, _name, _words}, migrations),
        do: [vault() | assistant()] ++ [usage()],
        else: []

    [database(), migrations, store(), smtp()] ++
      of_the_database ++
      if address, do: [test_email(address)], else: []
  end

  @doc "Whether no result is a fault."
  @spec passed?([result]) :: boolean
  def passed?(results), do: Enum.all?(results, fn {status, _, _} -> status != :fail end)

  @doc "The results as lines of text."
  @spec format([result]) :: String.t()
  def format(results) do
    Enum.map_join(results, "\n", fn {status, name, words} ->
      label = %{ok: "ok  ", note: "note", fail: "FAIL"} |> Map.fetch!(status)
      "#{label}  #{String.pad_trailing(name, 10)} #{words}"
    end)
  end

  @doc "The database answers, and its version is 18 or later."
  @spec database() :: result
  def database do
    sql = "select current_setting('server_version_num')::int, current_setting('server_version')"

    case Repo.query(sql, [], timeout: 5_000) do
      {:ok, %{rows: [[number, version]]}} when number >= @postgres_minimum ->
        {:ok, "database", "PostgreSQL #{version}"}

      {:ok, %{rows: [[_number, version]]}} ->
        {:fail, "database", "PostgreSQL #{version}: Rescord needs PostgreSQL 18 or later"}

      {:error, error} ->
        {:fail, "database", "no answer: #{Exception.message(error)}"}
    end
  rescue
    error -> {:fail, "database", "no answer: #{Exception.message(error)}"}
  end

  @doc "The migrations of the database and of each organisation that have not run."
  @spec migrations() :: result
  def migrations do
    pending = count_pending(Ecto.Migrator.migrations(Repo))
    tenant_path = Ecto.Migrator.migrations_path(Repo, "tenant_migrations")

    tenants =
      if pending == 0,
        do:
          Enum.map(
            Repo.all_tenants(),
            &count_pending(Ecto.Migrator.migrations(Repo, [tenant_path], prefix: &1))
          ),
        else: []

    case pending + Enum.sum(tenants) do
      0 -> {:ok, "migrations", "each migration has run"}
      count -> {:note, "migrations", "#{count} have not run: the next start runs them"}
    end
  rescue
    error -> {:fail, "migrations", "cannot read: #{Exception.message(error)}"}
  end

  @doc "The store takes a file, gives the same bytes back, and deletes it."
  @spec store() :: result
  def store do
    store = Storage.store()

    key =
      Storage.key("check", ["probe", Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)])

    bytes = "Rescord checks its store.\n"

    with {:put, :ok} <- {:put, store.put(key, bytes, "text/plain")},
         {:get, {:ok, ^bytes}} <- {:get, store.get(key)},
         {:delete, :ok} <- {:delete, store.delete(key)} do
      remove_empty_directories(store)
      {:ok, "store", "#{Storage.describe(store)} takes, gives back and deletes a file"}
    else
      {step, result} ->
        {:fail, "store",
         "#{Storage.describe(store)}: the #{step} of a file gave #{inspect(result)}"}
    end
  rescue
    error -> {:fail, "store", Exception.message(error)}
  end

  @doc """
  The SMTP server takes the connection, the TLS and the user of the
  settings. It sends nothing.
  """
  @spec smtp() :: result
  def smtp do
    config = Application.get_env(:rescord, Mailer, [])

    case Keyword.get(config, :adapter) do
      Swoosh.Adapters.SMTP ->
        smtp_session(config)

      adapter ->
        {:note, "mail", "#{inspect(adapter)} sends the mail: there is no SMTP server to check"}
    end
  end

  defp smtp_session(config) do
    options = config |> Keyword.delete(:adapter) |> Swoosh.Adapters.SMTP.gen_smtp_config()
    server = "#{config[:relay]}:#{config[:port]}"

    case :gen_smtp_client.open(options) do
      {:ok, socket} ->
        :gen_smtp_client.close(socket)
        {:ok, "mail", "#{server} takes the connection#{tls_words(config)}#{user_words(config)}"}

      {:error, _type, reason} ->
        {:fail, "mail", "#{server}: #{smtp_reason(reason)}"}
    end
  end

  defp tls_words(config) do
    cond do
      config[:ssl] -> " over TLS"
      config[:tls] == :always -> " with STARTTLS"
      true -> ", with no TLS"
    end
  end

  defp user_words(config) do
    if config[:auth] == :always, do: ", and the user #{config[:username]}", else: ""
  end

  defp smtp_reason({:permanent_failure, _host, :auth_failed}),
    do: "the server refused the user and the password"

  defp smtp_reason({:missing_requirement, _host, :auth}),
    do: "the server offers no sign-in, and the settings give a user"

  defp smtp_reason({:missing_requirement, _host, :tls}),
    do: "the server offers no STARTTLS: set RESCORD_SMTP_TLS to tls, or ask the provider"

  defp smtp_reason({:network_failure, _host, {:error, reason}}),
    do: "no connection: #{inspect(reason)}"

  defp smtp_reason(reason), do: inspect(reason)

  @doc """
  The values that the secret of the server encrypts: the secrets of the
  settings in `Rescord.Vault`, and the private keys of the transfers
  (ADR 0068). Each must open with `RESCORD_KEY_SECRET`. While the secret
  changes, some open with `RESCORD_KEY_SECRET_PREVIOUS`, and
  `bin/rotate-vault` writes them again.
  """
  @spec vault() :: result
  def vault do
    counts = Map.merge(Vault.count(), Transfers.count_keys(), fn _kind, a, b -> a + b end)
    total = counts.current + counts.previous + counts.sealed
    previous? = is_binary(Application.get_env(:rescord, Vault, [])[:previous_secret])

    case counts do
      %{sealed: sealed} when sealed > 0 ->
        {:fail, "vault",
         "#{some(sealed, total)} with no secret of this server: " <>
           "RESCORD_KEY_SECRET is not the secret that encrypted the rest"}

      %{previous: previous} when previous > 0 ->
        {:note, "vault",
         "#{some(previous, total)} with the previous secret alone: run bin/rotate-vault"}

      _each_current when total == 0 ->
        {:ok, "vault", "no encrypted value yet"}

      _each_current when previous? ->
        {:note, "vault",
         "#{each(total)} opens with the secret of today: take RESCORD_KEY_SECRET_PREVIOUS out"}

      _each_current ->
        {:ok, "vault", "#{each(total)} opens with the secret of this server"}
    end
  rescue
    _error -> {:fail, "vault", "cannot read the encrypted values"}
  end

  defp some(1, total), do: "1 of #{total} encrypted values opens"
  defp some(count, total), do: "#{count} of #{total} encrypted values open"

  defp each(1), do: "the one encrypted value"
  defp each(total), do: "each of the #{total} encrypted values"

  @doc """
  What the server does with its usage counts: nothing, keep them, or also
  send them. With the sending on, a last send that failed is a fault. The
  line names no address: an address can hold a secret in its path. It
  reads the row, and sends nothing.
  """
  @spec usage() :: result
  def usage do
    case Usage.settings(authorize?: false) do
      %{mode: :off} ->
        {:note, "usage", "the counts are off. A root user turns them on at /root/usage"}

      %{mode: :local} ->
        {:ok, "usage", "kept on this server, and sent nowhere"}

      %{mode: :send, last_result: result} when result not in [nil, :ok] ->
        {:fail, "usage", "sent each day, and the last send failed (#{result}). See /root/usage"}

      %{mode: :send, last_sent_day: nil} ->
        {:ok, "usage", "sent each day to the address of /root/usage. No day is sent yet"}

      %{mode: :send, last_sent_day: day} ->
        {:ok, "usage",
         "sent each day to the address of /root/usage. Each day up to #{Date.to_iso8601(day)} is done"}
    end
  rescue
    _error -> {:fail, "usage", "cannot read the settings of the usage counts"}
  end

  @doc """
  A line for each provider of the assistant: where the records go, whether
  it has what a request needs, whether an organisation can choose it, and
  what its last test found. It reads the rows, sends no request, and
  decrypts and prints no key: a person with a shell gets no way to spend
  money here.
  """
  @spec assistant() :: [result]
  def assistant do
    case Ruby.providers_for_check() do
      [] -> [{:note, "assistant", "no provider yet. A root user adds one at /root/ruby"}]
      providers -> Enum.map(providers, &provider_line/1)
    end
  rescue
    _error -> [{:fail, "assistant", "cannot read the providers"}]
  end

  defp provider_line(provider) do
    words =
      "#{provider.name}: the model #{provider.model}, records go to #{Ruby.place(provider)}"

    cond do
      (problems = Ruby.provider_problems(provider)) != [] ->
        {_field, problem} = hd(problems)
        {:fail, "assistant", words <> ": " <> problem}

      not provider.offered ->
        {:note, "assistant", words <> ". Not offered to an organisation"}

      provider.test_result == :ok ->
        {:ok, "assistant", words <> ". The last test passed on #{day(provider.tested_at)}"}

      is_nil(provider.tested_at) ->
        {:note, "assistant", words <> ". Never tested: press Test at /root/ruby"}

      true ->
        {:fail, "assistant",
         words <>
           ". The last test failed on #{day(provider.tested_at)}: #{provider.test_result}"}
    end
  end

  defp day(%DateTime{} = instant), do: Calendar.strftime(instant, "%-d %B %Y")

  @doc "Sends a short email to `address`, through the mailer of the settings."
  @spec test_email(String.t()) :: result
  def test_email(address) do
    case address |> Rescord.Mail.mail_works() |> Mailer.deliver() do
      {:ok, _receipt} ->
        {:ok, "email", "sent to #{address}: look for it in that inbox, and in its spam"}

      {:error, reason} ->
        {:fail, "email", "not sent to #{address}: #{smtp_reason(unwrap(reason))}"}
    end
  end

  defp unwrap({_type, reason}), do: reason
  defp unwrap(reason), do: reason

  # A store in a directory keeps the empty directories of the key.
  defp remove_empty_directories(store) do
    if root = Application.get_env(:rescord, store, [])[:root] do
      File.rmdir(Path.join([root, "check", "probe"]))
      File.rmdir(Path.join(root, "check"))
    end

    :ok
  end

  defp count_pending(migrations), do: Enum.count(migrations, &match?({:down, _, _}, &1))

  # The applications of the checks, and the repository with a small pool.
  defp start do
    for app <- [:ssl, :ecto_sql, :postgrex, :req, :gen_smtp, :swoosh, :ash] do
      {:ok, _} = Application.ensure_all_started(app)
    end

    case Repo.start_link(pool_size: 2) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end
end
