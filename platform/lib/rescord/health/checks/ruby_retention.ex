defmodule Rescord.Health.Checks.RubyRetention do
  @moduledoc """
  C5 of issue 38: a conversation with the assistant that is older than the
  days that the organisation keeps them (`retention_days` of its settings,
  90 with none). The settings promise that such a conversation is deleted
  for real (ADR 0069); `Rescord.Ruby.Workers.Tidy` does it
  each hour, so a conversation that stays means that job
  fails.

  The ids are those of the conversations.
  """

  use Rescord.Health.Check

  @impl true
  def name, do: :ruby_retention
  @impl true
  def scope, do: :organisation
  @impl true
  def cadence, do: :daily
  @impl true
  def title, do: "Conversations with the assistant kept after their days"

  @impl true
  def explain,
    do:
      "These conversations are older than the days that the settings of the assistant keep " <>
        "them. Rescord deletes them each hour: look in the log for the job of the assistant."

  @impl true
  def run(%{now: now} = context) do
    query(
      """
      select c.id from #{table(context, "ruby_conversations")} c
      where c.last_message_at < $1::timestamp - make_interval(days => coalesce(
        (select s.retention_days from #{table(context, "ruby_settings")} s
          where s.valid_at @> $2::timestamptz limit 1), 90)::int)
      """,
      [DateTime.to_naive(now), now]
    )
    |> found(:fail)
  end
end
