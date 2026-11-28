defmodule Rescord.Health.Alerts do
  @moduledoc """
  The alerts of the sanity checks (ADR 0114, issue 38, section 9): a
  message to each root user who watches (`Rescord.Health.Watcher`), on
  each channel of notifications that the person set up and the server
  has, when a check fails.

  A result alerts when it starts to fail, and again each day that it still
  fails. `alerted_at` of the result holds when it last did; a result that
  stops failing forgets it (`Rescord.Health`), so the next fault alerts at
  once. A run with several results to alert sends one message to each
  person and channel.

  The message is a pointer, as each notification is (issue 29, section 5):
  "Rescord" as the title, one sentence, and the address of `/root/health`.
  It names no check, no organisation and no count: a phone shows it on its
  lock screen, and a topic of ntfy is open to anybody who knows its name.

  Each person and channel is one job of `Rescord.Health.Workers.Alert`,
  which tries again a fault that can pass, 5 times at most.
  """

  require Ash.Query

  alias Rescord.Health.{Result, Watcher}
  alias Rescord.Notifications.{Channel, Message}

  @again_after_hours 24

  @doc """
  Sends the alerts that are due at `now`: of each result that fails and
  did not alert in the last 24 hours. Returns how many jobs it started. With
  nobody to tell, it marks nothing, so a person who starts to watch hears
  of a fault at the next run.
  """
  @spec send_due(DateTime.t()) :: non_neg_integer
  def send_due(now \\ DateTime.utc_now()) do
    before = DateTime.add(now, -@again_after_hours, :hour)

    due =
      Result
      |> Ash.Query.filter(level == :fail and (is_nil(alerted_at) or alerted_at < ^before))
      |> Ash.read!(authorize?: false)

    users = watchers()

    if due == [] or users == [] do
      0
    else
      Enum.each(due, &mark(&1, now))

      jobs =
        for user_id <- users,
            channel <- Channel.all(),
            do: Rescord.Health.Workers.Alert.new(%{user_id: user_id, channel: channel.key()})

      jobs |> Oban.insert_all() |> length()
    end
  end

  @doc """
  Sends the alert to one person on one channel, if the person still
  watches and is a root user, and the server and the person have the
  channel. Answers as `Rescord.Notifications.Channel.deliver/3` does.
  """
  @spec deliver(Ecto.UUID.t(), atom) :: :ok | {:retry, atom}
  def deliver(user_id, key) do
    settings = Rescord.Notifications.settings_for_job()

    with true <- user_id in watchers(),
         channel when is_atom(channel) and not is_nil(channel) <-
           Enum.find(Channel.all(), &(&1.key() == key)),
         true <- channel.ready?(settings) do
      channel.deliver(message(), user_id, settings)
    else
      _nothing_to_send -> :ok
    end
  end

  @doc "The message of an alert."
  @spec message() :: Message.t()
  def message do
    {module, function} = Application.fetch_env!(:rescord, :health_page_url)

    %Message{
      title: "Rescord",
      body: "A sanity check of the server found a fault.",
      url: apply(module, function, []),
      tag: "health"
    }
  end

  # The users who watch and are root users now.
  defp watchers do
    Watcher
    |> Ash.Query.filter(user.root? == true)
    |> Ash.Query.select([:user_id])
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.user_id)
  end

  defp mark(result, now) do
    result
    |> Ash.Changeset.for_update(:alerted, %{alerted_at: now}, authorize?: false)
    |> Ash.update!()
  end
end
