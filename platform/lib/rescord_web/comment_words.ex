defmodule RescordWeb.CommentWords do
  @moduledoc """
  The words of the comments and the notifications (issue 29): the kinds of
  record, the kinds of notification, the devices and the channels, and the
  times of a comment.
  """

  alias Rescord.Accounts
  alias RescordWeb.JournalWords

  @doc "An instant in the time zone of the organisation, in words."
  @spec instant(map, DateTime.t()) :: String.t()
  def instant(organisation, %DateTime{} = instant),
    do: JournalWords.time(Accounts.local_time(organisation, instant))

  @doc "A kind of record, after \"a\" or \"an\"."
  @spec record(atom) :: String.t()
  def record(:resident), do: "a resident"
  def record(:task), do: "a task"
  def record(:expense), do: "an expense"
  def record(:transfer), do: "a transfer"

  @doc """
  A person whom a comment names, from `Rescord.Comments.people/2`: the
  address, with "(former member)" for a person who left the organisation,
  and "a former member" alone for a user who is gone from the server.
  """
  @spec person(map, Ecto.UUID.t()) :: String.t()
  def person(people, user_id) do
    case Map.get(people, user_id) do
      {email, :member} -> email
      {email, :former} -> "#{email} (former member)"
      nil -> "a former member"
    end
  end

  @doc "What a notification says, with its writer."
  @spec notification(atom, String.t(), atom) :: String.t()
  def notification(:told, "a former member", record),
    do: "A former member told you about a comment on #{record(record)}"

  def notification(:told, writer, record),
    do: "#{writer} told you about a comment on #{record(record)}"

  def notification(:comment, writer, record),
    do: "A comment by #{writer} on #{record(record)} that you follow"

  @doc "A kind of notification, for the boxes of the channels."
  @spec kind(atom) :: String.t()
  def kind(:told), do: "When somebody tells me about a comment"
  def kind(:comment), do: "A new comment on a record that I follow"

  @doc "A channel, for the boxes of the channels."
  @spec channel(atom) :: String.t()
  def channel(:web_push), do: "On my devices"
  def channel(:ntfy), do: "On ntfy"

  @doc "A kind of device, which the browser said."
  @spec device(atom) :: String.t()
  def device(:iphone), do: "An iPhone"
  def device(:ipad), do: "An iPad"
  def device(:android), do: "An Android device"
  def device(:mac), do: "A Mac"
  def device(:windows), do: "A Windows computer"
  def device(:linux), do: "A Linux computer"
  def device(:other), do: "A device"
end
