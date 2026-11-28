defmodule Rescord.Transfers.Grants do
  @moduledoc """
  What a role can do with the partnerships and the transfers (ADR 0024 and
  ADR 0042).

  The power `:transfers` asks a refuge to be a partner, answers such a
  question, ends a partnership, sends a resident to a partner, and accepts,
  declines or withdraws a transfer, and sends one whose files did not
  arrive again (ADR 0100). With a partner on another server, it
  records the partner card, ends the partnership, and exports and imports
  a transfer file (ADR 0043), and checks the files of an import again when
  the virus scan did not answer (issue 37). The administrators have it at
  first.

  The reads are not here: a partnership and a transfer are outside the
  schemas, and `Rescord.Transfers.Checks.MemberOf` decides what a person
  reads of them.
  """

  @behaviour Rescord.Accounts.Grants

  alias Rescord.Transfers.{Partnership, RemotePartner, Transfer}

  @impl true
  def reads, do: []

  @impl true
  def powers do
    %{
      transfers:
        for(action <- [:ask, :accept, :decline, :end], do: {Partnership, action, :all}) ++
          for(
            action <- [
              :send,
              :send_again,
              :accept,
              :decline,
              :withdraw,
              :export,
              :import,
              :check_again
            ],
            do: {Transfer, action, :all}
          ) ++
          for(action <- [:record, :end], do: {RemotePartner, action, :all})
    }
  end
end
