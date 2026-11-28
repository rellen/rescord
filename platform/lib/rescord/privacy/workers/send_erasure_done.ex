defmodule Rescord.Privacy.Workers.SendErasureDone do
  @moduledoc """
  Sends the person the email that says what an erasure did and what stays
  (ADR 0105, issue 31, call 13). `Rescord.Privacy.erase/3` writes the job
  in its transaction, so the job is there only when the erasure is, and
  it runs after the commit. A fault of the mail server returns an error,
  and Oban runs the job again later.

  The arguments hold the address until the pruner of Oban deletes the job,
  one day after it ran. Then the request records the day that the person
  was told. The log names the kind of a fault, and never the address.
  """

  use Oban.Worker, queue: :default, max_attempts: 10

  require Logger

  alias Rescord.Privacy

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{"to" => to, "organisation" => organisation, "label" => label, "kept" => kept} = args

    case Rescord.Mailer.deliver(Rescord.Mail.erasure_done(to, organisation, label, kept)) do
      {:ok, _receipt} ->
        note_told(args)

      {:error, reason} ->
        Logger.warning("The email of an erasure failed: #{Rescord.Log.reason(reason)}")
        {:error, :not_sent}
    end
  end

  defp note_told(%{"request_id" => id, "tenant" => tenant}) do
    with {:ok, %{} = request} <- Privacy.request(id, tenant: tenant, authorize?: false) do
      Privacy.note_told(request, Rescord.Accounts.today(tenant),
        tenant: tenant,
        authorize?: false
      )
    end

    :ok
  end

  defp note_told(_args), do: :ok
end
