defmodule Rescord.Notifications.Channel do
  @moduledoc """
  A way that a notification reaches a person outside the app (issue 29,
  section 11): Web Push (`Rescord.Notifications.Channels.WebPush`) and
  ntfy (`Rescord.Notifications.Channels.Ntfy`). Another channel is another
  module of this behaviour, and a line of `all/0`: no change to a
  notification or to a preference.

  A channel sends a `Rescord.Notifications.Message`: a pointer, with the
  name of the organisation, one sentence of the kind and the address of the
  page of notifications. Never a record, a person or a word of a comment.

  `deliver/3` sends to each address of the person on the channel (each
  device, the topic), and answers:

    * `:ok` - it sent, or the person has no address there;
    * `{:retry, reason}` - a fault that can pass, such as a push service
      that did not answer: the job tries this channel again later.

  An address that the service says is gone, the channel forgets by itself.
  """

  alias Rescord.Notifications.{Message, Settings}

  @doc "The key of the channel in a preference, such as `:web_push`."
  @callback key() :: atom

  @doc "Whether the server sends on the channel: a root user turned it on."
  @callback ready?(Settings.t()) :: boolean

  @doc "Whether the person has an address on the channel."
  @callback set_up?(Ecto.UUID.t()) :: boolean

  @doc "Sends the message to each address of the person on the channel."
  @callback deliver(Message.t(), Ecto.UUID.t(), Settings.t()) :: :ok | {:retry, atom}

  @doc "The channels, in the order of the page."
  @spec all() :: [module]
  def all, do: [Rescord.Notifications.Channels.WebPush, Rescord.Notifications.Channels.Ntfy]

  @doc "The keys of the channels."
  @spec keys() :: [atom]
  def keys, do: Enum.map(all(), & &1.key())

  @doc """
  The options of a request to a service of a channel. The tests give a
  `Req.Test` plug here (`config/test.exs`): it is no setting of a server.
  """
  @spec request_options() :: keyword
  def request_options do
    [
      redirect: false,
      retry: false,
      connect_options: [timeout: 10_000],
      receive_timeout: 20_000
    ]
    |> Keyword.merge(Keyword.get(Application.get_env(:rescord, __MODULE__, []), :req_options, []))
  end
end
