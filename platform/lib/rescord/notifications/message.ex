defmodule Rescord.Notifications.Message do
  @moduledoc """
  What a channel sends for a notification: a pointer (issue 29, section 5).
  The name of the organisation, one sentence of the kind, and the address
  of the page of notifications of the organisation. It names no record, no
  person and no word of a comment: a phone shows it on its lock screen,
  and a topic of ntfy is open to anybody who knows its name.

  `config :rescord, :notifications_page_url` names the function of the web
  layer that gives the address, as the sign-in link does.
  """

  @enforce_keys [:title, :body, :url, :tag]
  defstruct [:title, :body, :url, :tag]

  @type t :: %__MODULE__{title: String.t(), body: String.t(), url: String.t(), tag: String.t()}

  @doc "The message of a notification in an organisation."
  @spec for(map, map) :: t
  def for(%{kind: kind, id: id}, %{name: name, short_name: short_name}) do
    {module, function} = Application.fetch_env!(:rescord, :notifications_page_url)

    %__MODULE__{
      title: name,
      body: sentence(kind),
      url: apply(module, function, [short_name]),
      tag: id
    }
  end

  @doc "The sentence of a kind of notification."
  @spec sentence(atom) :: String.t()
  def sentence(:told), do: "Somebody told you about a comment."
  def sentence(:comment), do: "A new comment on a record that you follow."

  @doc "The message as the JSON that the service worker of Rescord reads."
  @spec json(t) :: String.t()
  def json(%__MODULE__{} = message),
    do:
      JSON.encode!(%{
        title: message.title,
        body: message.body,
        url: message.url,
        tag: message.tag
      })
end
