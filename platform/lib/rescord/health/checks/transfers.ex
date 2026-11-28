defmodule Rescord.Health.Checks.Transfers do
  @moduledoc """
  C22 of issue 38: transfers that are stuck (ADR 0100).

    * A fault: a transfer `failed` that was sent more than 7 days ago, or a
      transfer whose job copied more files than it has.
    * A note: a transfer `sent` more than 14 days ago with no answer.

  The ids are those of the transfers.
  """

  use Rescord.Health.Check

  @impl true
  def name, do: :transfers
  @impl true
  def scope, do: :server
  @impl true
  def cadence, do: :daily
  @impl true
  def title, do: "Transfers that are stuck"

  @impl true
  def explain,
    do:
      "A fault: a transfer failed and was sent more than 7 days ago, or counts more files " <>
        "copied than it has. The refuge that sent it sends it again from its page. A note: a " <>
        "transfer has waited 14 days for an answer."

  @impl true
  def run(%{now: now}) do
    params = [DateTime.to_naive(now)]

    case query(
           """
           select t.id from public.transfers t
           where (t.state = 'failed' and t.sent_at < $1::timestamp - interval '7 days')
             or t.files_copied > t.files_total
           """,
           params
         ) do
      {0, _ids} ->
        """
        select t.id from public.transfers t
        where t.state = 'sent' and t.sent_at < $1::timestamp - interval '14 days'
        """
        |> query(params)
        |> found(:note)

      faults ->
        found(faults, :fail)
    end
  end
end
