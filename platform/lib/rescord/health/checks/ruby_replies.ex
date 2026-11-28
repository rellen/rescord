defmodule Rescord.Health.Checks.RubyReplies do
  @moduledoc """
  C4 of issue 38: a reply of the assistant that stays `streaming` with no
  new word for 2 hours, or a message of a member with no reply after 2
  hours. Either one makes the conversation refuse each new message
  (`Rescord.Ruby.Replies`): a deploy or a crash during a reply leaves it so,
  and the job has one try. `Rescord.Ruby.Workers.Tidy` ends them each hour,
  6 minutes after their last change, so a reply that this check finds
  means that job stopped or fails.

  The ids are those of the messages.
  """

  use Rescord.Health.Check

  @impl true
  def name, do: :ruby_replies
  @impl true
  def scope, do: :organisation
  @impl true
  def cadence, do: :hourly
  @impl true
  def title, do: "Replies of the assistant that stopped"

  @impl true
  def explain,
    do:
      "A reply has had no word for 2 hours, or a message no reply, so its conversation takes " <>
        "no new message. The job of the assistant ends such a reply each hour, and the member " <>
        "can then try again: one that stays means that job stopped. Look in the log for it."

  @impl true
  def run(%{now: now} = context) do
    messages = table(context, "ruby_messages")

    query(
      """
      select m.id from #{messages} m
      where m.source = 'ruby' and m.state = 'streaming'
        and m.updated_at < $1::timestamp - interval '2 hours'
      union all
      select m.id from #{messages} m
      where m.source = 'user' and m.inserted_at < $1::timestamp - interval '2 hours'
        and not exists (select 1 from #{messages} r where r.response_to_id = m.id)
      """,
      [DateTime.to_naive(now)]
    )
    |> found(:fail)
  end
end
