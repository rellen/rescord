defmodule Rescord.Usage do
  @moduledoc """
  The usage counts of the server (ADR 0098, issue 23): how often each
  feature is used, for each day, for the whole server. A count holds a day,
  a feature of `Rescord.Usage.Features`, a kind (`page`, `action`, `file`),
  the name of the page, action or file as the code names it, and a number.
  It holds nothing of a person, of an organisation or of a record.

  ## Where a count comes from

  From the `:telemetry` events that Ash and Phoenix emit already. The
  actions come from `Rescord.Usage.Actions`, here in the core; the pages
  and the files from `RescordWeb.Usage`. Each calls `count/3`, which adds
  one in memory (`Rescord.Usage.Counter`) and emits the event
  `[:rescord, :usage, :count]`, whose counter `rescord.usage.count` is on
  the metrics endpoint of ADR 0077. `flush/0` writes the memory to the
  database each minute.

  ## Where the counts go

  The settings (`Rescord.Usage.Settings`) have a mode, which a root user
  sets on `/root/usage`:

  - `off`: nothing is counted, and nothing new is stored;
  - `local`, the default: the counts stay on the server, for its root users;
  - `send`: the job `Rescord.Usage.Workers.Send` also sends each full day
    to the one address that a root user named, as OTLP or as the plain
    document (`Rescord.Usage.Document`).

  Nothing leaves a server until a root user names an address. Rescord has
  no address of its own in the code.

  No setting of the counts is in the environment or in the application
  config (ADR 0068). The token of the address is encrypted in
  `Rescord.Vault`, and `Rescord.Usage.Sender` is the one module that
  decrypts it.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  require Ash.Query
  require Logger

  alias Rescord.Usage.{Count, Counter, Document, Features, Sender, Settings}

  boundary do
    check aliases: true
    deps [Rescord, Rescord.Accounts, Rescord.Vault]

    exports [
      Rescord.Usage.Actions,
      Counter,
      Document,
      Features,
      Rescord.Usage.Workers.Send
    ]
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Count do
      define :add_count, action: :add, args: [:day, :feature, :kind, :item, :by]
    end

    resource Settings do
      define :start_settings, action: :start
      define :change_settings, action: :change
      define :set_token, action: :set_token, args: [:token]
      define :forget_token, action: :forget_token
      define :new_installation, action: :new_installation
    end
  end

  @mode {__MODULE__, :mode}
  @kept_days 400
  @catch_up_days 7

  @typedoc "What a server does with its counts."
  @type mode :: :off | :local | :send

  ## Counting

  @doc """
  Counts one use of `feature`: a page that opened, an action that a person
  ran, or a file that Rescord sent. `item` names it as the code does. It
  does nothing in the mode `off`, and never raises.
  """
  @spec count(Features.t(), :page | :action | :file, String.t()) :: :ok
  def count(feature, kind, item) when is_atom(feature) and is_binary(item) do
    if mode() != :off do
      Counter.add({feature, kind, item})
      :telemetry.execute([:rescord, :usage, :count], %{count: 1}, %{feature: feature, kind: kind})
    end

    :ok
  end

  @doc """
  The mode of this node, from memory. It is `local` until the node read the
  settings, and the counts of that time are not written in the mode `off`.
  """
  @spec mode() :: mode
  def mode, do: :persistent_term.get(@mode, :local)

  @doc """
  Reads the mode from the database, into memory. The counter does it at the
  start and each minute, so that a change on one node reaches the others.
  A fault of the database keeps the mode that was there.
  """
  @spec read_mode() :: mode
  def read_mode do
    case Ash.read_one(Settings, authorize?: false) do
      {:ok, %Settings{mode: mode}} -> remember_mode(mode)
      {:ok, nil} -> remember_mode(:local)
      {:error, _error} -> mode()
    end
  rescue
    # The database of a new server has no table yet, or is not there.
    _error -> mode()
  catch
    :exit, _reason -> mode()
  end

  # A write of a persistent term costs each process a scan, so only a
  # change writes.
  defp remember_mode(mode) do
    if mode() != mode, do: :persistent_term.put(@mode, mode)
    mode
  end

  @doc """
  Writes the counts of the memory to the database, as upserts that add.
  A count that could not be written goes back into the memory, for the next
  time. In the mode `off`, the memory is emptied and nothing is written.
  """
  @spec flush() :: :ok
  def flush do
    if mode() == :off do
      Counter.clear()
    else
      counts = Counter.take_all()
      failed = Enum.reject(counts, &write/1)
      Counter.put_back(failed)
    end

    :ok
  end

  defp write({{day, feature, kind, item}, number}) do
    match?({:ok, _count}, add_count(day, feature, kind, item, number, authorize?: false))
  rescue
    _error -> false
  catch
    :exit, _reason -> false
  end

  ## The settings and the counts, for a root user

  @doc """
  The settings of the server, or a row that is not saved with the defaults,
  for a server whose root user saved nothing yet.
  """
  @spec settings(keyword) :: Settings.t()
  def settings(opts) do
    case Ash.read_one(Settings, opts) do
      {:ok, %Settings{} = settings} -> settings
      _none -> struct(Settings, mode: :local, format: :otlp)
    end
  end

  @doc """
  Saves the mode, the format and the address. The first save makes the row
  of the server, with its random installation id.
  """
  @spec save_settings(map, keyword) :: {:ok, Settings.t()} | {:error, term}
  def save_settings(attributes, opts) do
    with {:ok, settings} <- row(opts),
         {:ok, settings} <- change_settings(settings, attributes, opts) do
      remember_mode(settings.mode)
      {:ok, settings}
    end
  end

  @doc "Sets the token of the address."
  @spec save_token(String.t(), keyword) :: {:ok, Settings.t()} | {:error, term}
  def save_token(token, opts) do
    with {:ok, settings} <- row(opts), do: set_token(settings, token, opts)
  end

  @doc "Makes a new installation id."
  @spec renew_installation(keyword) :: {:ok, Settings.t()} | {:error, term}
  def renew_installation(opts) do
    with {:ok, settings} <- row(opts), do: new_installation(settings, opts)
  end

  # The row of the server, made when it is not there.
  defp row(opts) do
    case Ash.read_one(Settings, opts) do
      {:ok, %Settings{} = settings} ->
        {:ok, settings}

      {:ok, nil} ->
        case start_settings(opts) do
          {:ok, settings} -> {:ok, settings}
          # Two root users at once: the other one made it.
          {:error, _error} -> Ash.read_one(Settings, opts) |> found()
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp found({:ok, %Settings{} = settings}), do: {:ok, settings}
  defp found({:ok, nil}), do: {:error, :not_found}
  defp found(other), do: other

  @doc """
  The counts of the days from `since` to today, as rows. The policy lets
  only a root user read them.
  """
  @spec counts_since(Date.t(), keyword) :: [Count.t()]
  def counts_since(%Date{} = since, opts) do
    Count
    |> Ash.Query.filter(day >= ^since)
    |> Ash.read!(opts)
  end

  @doc """
  The newest full day with a count, before `today`, or `nil`. The page
  shows its document.
  """
  @spec last_full_day(Date.t(), keyword) :: Date.t() | nil
  def last_full_day(%Date{} = today, opts) do
    Count
    |> Ash.Query.filter(day < ^today)
    |> Ash.Query.sort(day: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one(opts)
    |> case do
      {:ok, %Count{day: day}} -> day
      _none -> nil
    end
  end

  @doc "The counts of one day, as rows."
  @spec counts_of(Date.t(), keyword) :: [Count.t()]
  def counts_of(%Date{} = day, opts) do
    Count
    |> Ash.Query.filter(day == ^day)
    |> Ash.read!(opts)
  end

  @doc """
  The document that a send of `day` writes, with the format and the
  installation id of `settings`. A server whose root user saved nothing yet
  has no installation id: the page shows a placeholder for it.
  """
  @spec document(Settings.t(), Date.t(), [Count.t()]) :: String.t()
  def document(%Settings{} = settings, day, counts) do
    Document.day(settings.format, installation(settings), day, counts)
  end

  defp installation(%Settings{installation_id: nil}), do: "00000000-0000-0000-0000-000000000000"
  defp installation(%Settings{installation_id: id}), do: id

  @doc "Deletes each stored count. The policy lets only a root user do it."
  @spec forget_counts(keyword) :: :ok | {:error, term}
  def forget_counts(opts) do
    Counter.clear()

    case Ash.bulk_destroy(Count, :forget, %{}, Keyword.merge(opts, strategy: [:atomic])) do
      %Ash.BulkResult{status: :success} -> :ok
      %Ash.BulkResult{errors: errors} -> {:error, errors}
    end
  end

  ## Sending

  @doc """
  "Send a test": a document with no count, to the address of the saved
  settings, and the answer written on the settings.
  """
  @spec send_test(keyword) :: {:ok, Settings.t()} | {:error, term}
  def send_test(opts) do
    with {:ok, %Settings{endpoint: endpoint} = settings} when is_binary(endpoint) <- row(opts) do
      {result, status} =
        outcome(Sender.post(settings, Document.test(settings.format, settings.installation_id)))

      Logger.info("A test of the usage counts", result: result)

      Ash.update(
        settings,
        %{tested_at: DateTime.utc_now(), test_result: result, test_status: status},
        action: :note_test,
        authorize?: false
      )
    else
      {:ok, %Settings{}} -> {:error, :no_endpoint}
      other -> other
    end
  end

  @doc """
  The work of each hour (`Rescord.Usage.Workers.Send`): it deletes the
  counts older than #{@kept_days} days, and in the mode `send` it sends each
  full day that is not sent yet, oldest first. It sends no day before the
  day that sending was turned on, none older than #{@catch_up_days} days,
  and none with no count. It stops at the first day that the address did
  not take, for the next hour.
  """
  @spec send_due(Date.t()) :: :ok
  def send_due(%Date{} = today \\ Date.utc_today()) do
    prune(today)

    case Ash.read_one(Settings, authorize?: false) do
      {:ok, %Settings{mode: :send, endpoint: endpoint} = settings} when is_binary(endpoint) ->
        send_days(settings, today)

      _other ->
        :ok
    end
  end

  defp send_days(settings, today) do
    yesterday = Date.add(today, -1)

    first =
      Enum.max(
        [
          settings.sending_since,
          settings.last_sent_day && Date.add(settings.last_sent_day, 1),
          Date.add(today, -@catch_up_days)
        ]
        |> Enum.reject(&is_nil/1),
        Date
      )

    if Date.compare(first, yesterday) == :gt do
      :ok
    else
      counts =
        Count
        |> Ash.Query.filter(day >= ^first and day <= ^yesterday)
        |> Ash.read!(authorize?: false)
        |> Enum.group_by(& &1.day)

      days = counts |> Map.keys() |> Enum.sort(Date)
      send_each(settings, days, counts, yesterday)
    end
  end

  # Each day in turn. After the last one, the days up to yesterday are done:
  # the ones in between had no count.
  defp send_each(%Settings{last_sent_day: yesterday}, [], _counts, yesterday), do: :ok

  defp send_each(settings, [], _counts, yesterday) do
    note(settings, %{last_sent_day: yesterday})
    :ok
  end

  defp send_each(settings, [day | rest], counts, yesterday) do
    body = Document.day(settings.format, settings.installation_id, day, counts[day])
    {result, status} = outcome(Sender.post(settings, body))
    Logger.info("A send of the usage counts", result: result)

    attempt = %{last_attempt_at: DateTime.utc_now(), last_result: result, last_status: status}

    case result do
      :ok ->
        case note(settings, Map.put(attempt, :last_sent_day, day)) do
          {:ok, settings} -> send_each(settings, rest, counts, yesterday)
          {:error, _error} -> :ok
        end

      _failed ->
        note(settings, Map.put(attempt, :last_sent_day, before(day, settings.last_sent_day)))
        :ok
    end
  end

  # The days before a day that failed are done.
  defp before(day, last_sent_day) do
    previous = Date.add(day, -1)

    if last_sent_day && Date.compare(last_sent_day, previous) == :gt,
      do: last_sent_day,
      else: previous
  end

  defp note(settings, attributes) do
    Ash.update(settings, attributes, action: :note_send, authorize?: false)
  end

  defp outcome({:ok, status}), do: {:ok, status}
  defp outcome({:status, status}), do: {:status, status}
  defp outcome(:unreachable), do: {:unreachable, nil}
  defp outcome(:sealed), do: {:sealed, nil}

  @doc "Deletes the counts that are older than #{@kept_days} days."
  @spec prune(Date.t()) :: :ok
  def prune(%Date{} = today) do
    cutoff = Date.add(today, -@kept_days)

    Count
    |> Ash.Query.filter(day < ^cutoff)
    |> Ash.bulk_destroy(:forget, %{}, authorize?: false, strategy: [:atomic])

    :ok
  end

  @doc """
  The problems of a refused change of the settings, as `{field, words}`,
  with `nil` for a problem of no field.
  """
  @spec problems(term) :: [{atom | nil, String.t()}]
  def problems(%{errors: errors}) when is_list(errors) do
    errors |> Enum.flat_map(&problem/1) |> Enum.uniq()
  end

  def problems(_error), do: [{nil, "That did not work"}]

  defp problem(%Ash.Error.Changes.Required{field: :token}), do: [{:token, "type the token"}]
  defp problem(%Ash.Error.Changes.Required{field: :mode}), do: [{:mode, "choose a mode"}]
  defp problem(%Ash.Error.Changes.Required{field: :format}), do: [{:format, "choose a format"}]
  defp problem(%Ash.Error.Forbidden.Policy{}), do: [{nil, "You cannot do that"}]

  defp problem(%{field: field, message: message} = error)
       when is_atom(field) and not is_nil(field) and is_binary(message),
       do: [{field, with_values(message, Map.get(error, :vars))}]

  # An error of a hook in the transaction holds the errors of the action.
  defp problem(%{errors: [_ | _]} = inner), do: problems(inner)
  defp problem(_other), do: [{nil, "That did not work"}]

  # A message of Ash can name a value of the rule, as in `must be less than
  # or equal to %{max}`. The values are beside the message.
  defp with_values(message, vars) when is_list(vars) or is_map(vars) do
    Enum.reduce(vars, message, fn {key, value}, message ->
      String.replace(message, "%{#{key}}", to_string(value))
    end)
  end

  defp with_values(message, _vars), do: message

  @doc "The days that the counts are kept."
  @spec kept_days() :: pos_integer
  def kept_days, do: @kept_days

  @doc "The most days that a send catches up after a time with no answer."
  @spec catch_up_days() :: pos_integer
  def catch_up_days, do: @catch_up_days
end
