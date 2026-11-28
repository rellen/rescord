defmodule Rescord.Ruby.Workers.Tidy do
  @moduledoc """
  The job that keeps the conversations of Ruby to what may stay (ADR 0069).
  Oban runs it each hour (`config/config.exs`). For each organisation it:

    * deletes the conversations whose last message is older than the days
      of the settings (`retention_days`, 90 to start), with their messages;
    * deletes the conversations of a person who is no member any more: they
      go with the membership;
    * ends a reply that hangs: one in `:streaming` whose row has not changed
      for six minutes is `:failed` with the reason `:unknown`, and a page
      that shows it hears so. A request to the provider takes five minutes
      at most, and a reply writes its row as its words grow, so a reply in
      that state has lost its job. A message of a member whose job died
      before it made the reply gets one, failed in the same way. The end
      is written only while the reply still streams, so a job that ended
      in between keeps its end, and a job that comes later writes nothing.

  The rows of the use stay: they hold counts and no words.

  The job takes the time as an argument, `now` (an ISO 8601 instant), so a
  test runs it on any day. Without one it takes the time of the server.

  A fault in one organisation goes to the log and does not stop the others.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Ash.Query
  require Logger

  alias Rescord.Accounts
  alias Rescord.Ruby
  alias Rescord.Ruby.{Conversation, Events, Message, Replies}

  # A reply whose row has not changed for this long has lost its job.
  @hangs_after 6 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    now = now(args)

    for organisation <- Accounts.all_organisations() do
      tidy(organisation, now)
    end

    :ok
  end

  defp now(%{"now" => text}) when is_binary(text) do
    {:ok, now, _offset} = DateTime.from_iso8601(text)
    now
  end

  defp now(_args), do: DateTime.utc_now()

  @doc """
  Tidies one organisation at the time `now`. Gives how many conversations
  went because of their age (`:old`) and because their member left
  (`:left`), and how many replies ended (`:hung`), or `:error` after a
  fault, which goes to the log.
  """
  @spec tidy(map, DateTime.t()) :: %{old: integer, left: integer, hung: integer} | :error
  def tidy(organisation, %DateTime{} = now) do
    days = Ruby.settings(organisation).retention_days
    before = DateTime.add(now, -days, :day)
    hung_before = DateTime.add(now, -@hangs_after, :second)

    # A member who joins after this read may start a conversation before
    # the delete: only a conversation from before the read can be of a
    # person who left.
    read_at = DateTime.utc_now()
    members = members(organisation)

    %{
      old: remove(organisation, Ash.Query.filter(Conversation, last_message_at < ^before)),
      left:
        remove(
          organisation,
          Ash.Query.filter(Conversation, owner_id not in ^members and inserted_at < ^read_at)
        ),
      hung: end_unanswered(organisation, hung_before) + end_hung(organisation, hung_before)
    }
  rescue
    error ->
      Logger.error(
        "The conversations of Ruby of the organisation #{organisation.id} were not tidied: " <>
          Rescord.Log.reason(error)
      )

      :error
  end

  # The users who are members now. An archived member is none.
  defp members(organisation) do
    Accounts.Member
    |> Ash.Query.select([:user_id])
    |> Ash.read!(tenant: organisation, authorize?: false)
    |> Enum.map(& &1.user_id)
  end

  # The messages go with each conversation in the database.
  defp remove(organisation, query) do
    %Ash.BulkResult{status: :success, records: records} =
      Ash.bulk_destroy!(query, :remove, %{},
        tenant: organisation,
        authorize?: false,
        strategy: [:atomic, :stream],
        return_records?: true
      )

    length(records)
  end

  # One statement ends each reply that still streams and has not changed:
  # a reply that the job ended in between is no longer `:streaming`, and
  # stays as the job wrote it. Only a reply that this statement ended is
  # told to its page.
  defp end_hung(organisation, before) do
    %Ash.BulkResult{status: :success, records: records} =
      Message
      |> Ash.Query.filter(state == :streaming and updated_at < ^before)
      |> Ash.bulk_update!(:close, %{state: :failed, reason: :unknown},
        tenant: organisation,
        authorize?: false,
        strategy: [:atomic],
        return_records?: true
      )

    Enum.each(records, &Events.reply(&1, :failed))
    length(records)
  end

  # A message of a member whose job died before it made the reply: the
  # conversation waits for that reply, so Tidy makes it, as failed. A job
  # that still comes finds the reply there, and stops (`:taken`).
  defp end_unanswered(organisation, before) do
    Message
    |> Ash.Query.filter(needs_reply and inserted_at < ^before)
    |> Ash.Query.select([:id, :conversation_id, :owner_id, :source])
    |> Ash.read!(tenant: organisation, authorize?: false)
    |> Enum.count(fn message ->
      with {:ok, reply} <- Replies.open(message, organisation),
           :ok <- Replies.close(reply, %{state: :failed, reason: :unknown}, organisation) do
        Events.reply(reply, :failed)
        true
      else
        _taken_or_gone -> false
      end
    end)
  end
end
