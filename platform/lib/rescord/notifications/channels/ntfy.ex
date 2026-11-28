defmodule Rescord.Notifications.Channels.Ntfy do
  @moduledoc """
  The channel of ntfy (issue 29, section 12): one message to the topic of
  the person (`Rescord.Notifications.NtfyTopic`), at the server of ntfy of
  the settings, with its access token when it has one.

  The message is the pointer of `Rescord.Notifications.Message`: the title,
  the sentence, and the address as the action `Click`. A topic is open to
  anybody who knows its name, so nothing more goes there.

  A 2xx is sent. 429, a 5xx and a fault of the network try again. Another
  answer drops the message, with a warning in the log.
  """

  @behaviour Rescord.Notifications.Channel

  require Ash.Query
  require Logger

  alias Rescord.Notifications.{Channel, Message, NtfyTopic, Secrets, Settings}

  @impl true
  def key, do: :ntfy

  @impl true
  def ready?(%Settings{ntfy_on: true, ntfy_url: url}) when is_binary(url), do: true
  def ready?(_settings), do: false

  @impl true
  def set_up?(user_id), do: topic_of(user_id) != nil

  @impl true
  def deliver(%Message{} = message, user_id, %Settings{} = settings) do
    with %NtfyTopic{} = topic <- topic_of(user_id),
         {:ok, %{topic: name}} when is_binary(name) <- Secrets.open(topic, :topic),
         {:ok, headers} <- headers(message, settings) do
      [
        url: String.trim_trailing(settings.ntfy_url, "/") <> "/" <> name,
        body: message.body,
        headers: headers
      ]
      |> Keyword.merge(Channel.request_options())
      |> Req.post()
      |> answer()
    else
      nil -> :ok
      {:retry, reason} -> {:retry, reason}
      _sealed -> {:retry, :sealed}
    end
  end

  defp topic_of(user_id) do
    NtfyTopic
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.read_one!(authorize?: false)
  end

  # A header of HTTP holds no line break, and ntfy reads the title as UTF-8.
  defp headers(message, settings) do
    base = [
      {"title", String.replace(message.title, ~r/[\r\n]+/, " ")},
      {"click", message.url},
      {"tags", "bell"},
      {"content-type", "text/plain; charset=utf-8"}
    ]

    case token(settings) do
      {:ok, nil} -> {:ok, base}
      {:ok, token} -> {:ok, [{"authorization", "Bearer " <> token} | base]}
      :sealed -> {:retry, :sealed}
    end
  end

  defp token(%Settings{ntfy_token_set_at: nil}), do: {:ok, nil}

  defp token(settings) do
    case Secrets.open(settings, :ntfy_token) do
      {:ok, %{ntfy_token: token}} when is_binary(token) or is_nil(token) -> {:ok, token}
      _other -> :sealed
    end
  end

  defp answer({:ok, %Req.Response{status: status}}) when status in 200..299, do: :ok

  defp answer({:ok, %Req.Response{status: status}}) when status == 429 or status >= 500,
    do: {:retry, :ntfy}

  defp answer({:ok, %Req.Response{status: status}}) do
    Logger.warning("The server of ntfy refused a message with the status #{status}")
    :ok
  end

  defp answer({:error, _exception}), do: {:retry, :unreachable}
end
