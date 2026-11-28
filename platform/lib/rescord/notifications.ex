defmodule Rescord.Notifications do
  @moduledoc """
  The notifications of the people of an organisation, and the channels that
  take them outside the app (issue 29, ADR 0106).

  A `Notification` is made by the listener of `:commented`
  (`Rescord.Comments.Signals`) for each person who follows the record of a
  new comment. It is in the app at once: the page of notifications and the
  count of the site header. A job then sends it on each channel that the
  person chose (`Rescord.Notifications.Preference`) and that the server
  has (`Rescord.Notifications.Settings`): Web Push to a device, a topic of
  ntfy. A channel carries a pointer only (`Rescord.Notifications.Message`).

  A person reads only their own notifications, devices, topic and
  preferences. Only a root user reads or changes the settings.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  require Ash.Query

  alias Rescord.Comments.Subject

  alias Rescord.Notifications.{
    Channel,
    Notification,
    NtfyTopic,
    Preference,
    PushSubscription,
    Secrets,
    Settings
  }

  boundary do
    # A relationship and a signal listener are checked too (ADR 0066).
    check aliases: true
    deps [Rescord, Rescord.Accounts, Rescord.Comments, Rescord.Vault]

    exports [
      Rescord.Notifications.Message,
      Rescord.Notifications.Channel
    ]
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Notification do
      define :notifications, action: :mine
      define :mark_read, action: :mark_read
    end

    resource Preference do
      define :set_preference, action: :set, args: [:kind, :channels]
    end

    resource PushSubscription do
      define :subscribe_device, action: :subscribe
      define :remove_device, action: :remove
    end

    resource NtfyTopic do
      define :start_ntfy, action: :start
      define :renew_ntfy, action: :renew
      define :stop_ntfy, action: :stop
    end

    resource Settings do
      define :start_settings, action: :start
      define :change_settings, action: :change
      define :make_settings_keys, action: :make_keys
      define :set_ntfy_token, action: :set_ntfy_token, args: [:ntfy_token]
      define :forget_ntfy_token, action: :forget_ntfy_token
    end
  end

  ## The notifications of a person

  @doc "How many notifications of the actor are new, in the organisation of `opts`."
  @spec unread_count(keyword) :: non_neg_integer
  def unread_count(opts) do
    case Keyword.get(opts, :actor) do
      %{id: user_id} ->
        Notification
        |> Ash.Query.filter(user_id == ^user_id and is_nil(read_at))
        |> Ash.count!(opts)

      _nobody ->
        0
    end
  end

  @doc """
  The newest notifications of the actor, each with its comment and the
  record of the comment, read as the actor. A notification whose comment
  the actor cannot read now is left out.
  """
  @spec notifications_with_records(keyword) :: {:ok, [Notification.t()]} | {:error, term}
  def notifications_with_records(opts) do
    load = [
      comment: [
        resident: [:name],
        task: [:title],
        expense: [:description],
        journal_entry: [:resident_id, resident: [:name]]
      ]
    ]

    with {:ok, notifications} <- notifications([load: load] ++ opts) do
      {:ok, Enum.filter(notifications, &match?(%{comment: %{}}, &1))}
    end
  end

  @doc """
  Marks as read each new notification of the actor about a record: the
  person opened the record.
  """
  @spec mark_read_on(Subject.t(), keyword) :: :ok
  def mark_read_on({kind, id}, opts) do
    case Keyword.get(opts, :actor) do
      %{id: user_id} ->
        column = Ash.Expr.ref([:comment], Subject.column(kind))

        Notification
        |> Ash.Query.filter(user_id == ^user_id and is_nil(read_at) and ^column == ^id)
        |> mark(opts)

      _nobody ->
        :ok
    end
  end

  @doc "Marks each new notification of the actor as read."
  @spec mark_all_read(keyword) :: :ok
  def mark_all_read(opts) do
    case Keyword.get(opts, :actor) do
      %{id: user_id} ->
        Notification
        |> Ash.Query.filter(user_id == ^user_id and is_nil(read_at))
        |> mark(opts)

      _nobody ->
        :ok
    end
  end

  defp mark(query, opts) do
    if Ash.exists?(query, opts) do
      Ash.bulk_update!(query, :mark_read, %{},
        actor: opts[:actor],
        tenant: opts[:tenant],
        strategy: [:atomic, :stream],
        notify?: true
      )
    end

    :ok
  end

  @doc """
  Deletes the old notifications of an organisation: each one 30 days after
  it was read, and each one 90 days after it was made. The job of each
  night runs it, with no person.
  """
  @spec prune(Ash.Resource.record() | String.t(), DateTime.t()) :: :ok
  def prune(tenant, %DateTime{} = now) do
    read_before = DateTime.add(now, -30, :day)
    made_before = DateTime.add(now, -90, :day)

    Notification
    |> Ash.Query.filter(read_at < ^read_before or inserted_at < ^made_before)
    |> Ash.bulk_destroy!(:forget, %{},
      tenant: tenant,
      authorize?: false,
      strategy: [:atomic, :stream],
      notify?: true
    )

    :ok
  end

  ## The channels of a person

  @doc """
  The channels of each kind of notification of the actor, as
  `%{kind => [channel key]}`. With no row, each channel.
  """
  @spec preferences(keyword) :: %{atom => [atom]}
  def preferences(opts) do
    rows =
      case Keyword.get(opts, :actor) do
        %{id: user_id} ->
          Preference |> Ash.Query.filter(user_id == ^user_id) |> Ash.read!(opts)

        _nobody ->
          []
      end

    defaults = Map.new(Notification.kinds(), &{&1, Channel.keys()})
    Enum.reduce(rows, defaults, &Map.put(&2, &1.kind, &1.channels))
  end

  @doc "The channels of one kind of notification of a person, for the job."
  @spec channels_for_job(Ecto.UUID.t(), atom, term) :: [atom]
  def channels_for_job(user_id, kind, tenant) do
    Preference
    |> Ash.Query.filter(user_id == ^user_id and kind == ^kind)
    |> Ash.read_one!(tenant: tenant, authorize?: false)
    |> case do
      %Preference{channels: channels} -> channels
      nil -> Channel.keys()
    end
  end

  @doc "The devices of the actor, the newest first."
  @spec devices(keyword) :: [PushSubscription.t()]
  def devices(opts) do
    PushSubscription
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(Keyword.delete(opts, :tenant))
  end

  @doc "The device of the actor with this id, or `nil`."
  @spec device(String.t(), keyword) :: PushSubscription.t() | nil
  def device(id, opts) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, device} <-
           Ash.get(
             PushSubscription,
             id,
             Keyword.delete(opts, :tenant) ++ [not_found_error?: false]
           ) do
      device
    else
      _none -> nil
    end
  end

  @doc "The topic of ntfy of the actor, or `nil`."
  @spec ntfy_topic(keyword) :: NtfyTopic.t() | nil
  def ntfy_topic(opts), do: Ash.read_one!(NtfyTopic, Keyword.delete(opts, :tenant))

  @doc """
  The address of the topic of ntfy of the actor, at the server of the
  settings, for the actor alone, or `nil`. This is where the name of a
  topic is decrypted for a page.
  """
  @spec ntfy_address(keyword) :: String.t() | nil
  def ntfy_address(opts) do
    with %NtfyTopic{} = topic <- ntfy_topic(opts),
         %Settings{ntfy_url: url} when is_binary(url) <- settings_for_job(),
         {:ok, %{topic: name}} when is_binary(name) <-
           Secrets.open_as(topic, :topic, opts) do
      String.trim_trailing(url, "/") <> "/" <> name
    else
      _none -> nil
    end
  end

  ## The settings of the server

  @doc """
  The settings of the server for a root user, or a row that is not saved,
  with the defaults.
  """
  @spec settings(keyword) :: Settings.t()
  def settings(opts) do
    case Ash.read_one(Settings, opts) do
      {:ok, %Settings{} = settings} -> settings
      _none -> struct(Settings, push_on: false, ntfy_on: false)
    end
  end

  @doc "The settings of the server with no person, for a job and a page of a member."
  @spec settings_for_job() :: Settings.t()
  def settings_for_job, do: settings(authorize?: false)

  @doc "What a page of a member may know of the settings: which channels the server has, and the public key."
  @spec offer() :: %{web_push: String.t() | nil, ntfy: boolean}
  def offer do
    settings = settings_for_job()

    %{
      web_push:
        if(Rescord.Notifications.Channels.WebPush.ready?(settings),
          do: settings.vapid_public_key
        ),
      ntfy: Rescord.Notifications.Channels.Ntfy.ready?(settings)
    }
  end

  @doc "Saves the plain fields of the settings. The first save makes the row."
  @spec save_settings(map, keyword) :: {:ok, Settings.t()} | {:error, term}
  def save_settings(attributes, opts) do
    with {:ok, settings} <- row(opts), do: change_settings(settings, attributes, opts)
  end

  @doc """
  Makes a new key pair of Web Push, and ends each subscription of a device,
  which the old key made: each person turns notifications on again.
  """
  @spec make_keys(keyword) :: {:ok, Settings.t()} | {:error, term}
  def make_keys(opts) do
    Ash.transact([Settings, PushSubscription], fn ->
      with {:ok, settings} <- row(opts),
           {:ok, settings} <- make_settings_keys(settings, opts) do
        Ash.bulk_destroy!(PushSubscription, :forget_all, %{},
          authorize?: false,
          strategy: [:atomic, :stream]
        )

        {:ok, settings}
      end
    end)
    |> case do
      {:ok, {:ok, settings}} -> {:ok, settings}
      {:ok, {:error, error}} -> {:error, error}
      {:error, error} -> {:error, error}
    end
  end

  @doc "Sets the access token of the server of ntfy."
  @spec save_ntfy_token(String.t(), keyword) :: {:ok, Settings.t()} | {:error, term}
  def save_ntfy_token(token, opts) do
    with {:ok, settings} <- row(opts), do: set_ntfy_token(settings, token, opts)
  end

  @doc "The number of devices of each person of the server, for a root user."
  @spec device_count() :: non_neg_integer
  def device_count, do: Ash.count!(PushSubscription, authorize?: false)

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
  The problems of a refused change, as `{field, words}`, with `nil` for a
  problem of no field.
  """
  @spec problems(term) :: [{atom | nil, String.t()}]
  def problems(%{errors: errors}) when is_list(errors),
    do: errors |> Enum.flat_map(&problem/1) |> Enum.uniq()

  def problems(_error), do: [{nil, "That did not work"}]

  defp problem(%Ash.Error.Forbidden.Policy{}), do: [{nil, "You cannot do that"}]

  defp problem(%Ash.Error.Changes.Required{field: :ntfy_token}),
    do: [{:ntfy_token, "type the token"}]

  defp problem(%{field: field, message: message})
       when is_atom(field) and not is_nil(field) and is_binary(message),
       do: [{field, message}]

  defp problem(%{errors: [_ | _]} = inner), do: problems(inner)
  defp problem(_other), do: [{nil, "That did not work"}]
end
