defmodule Rescord.Transfers.Checks.MemberOf do
  @moduledoc """
  The read of a partnership or a transfer (ADR 0042): a filter that holds
  what the actor can see.

    * A partnership: each one of an organisation of the actor.
    * A partner on another server: each one of an organisation of the actor.
    * A transfer: each one that an organisation of the actor sent; each one
      that it received and accepted; and each one that waits for an answer
      from an organisation where the role of the actor can accept it.
  """

  use Ash.Policy.FilterCheck

  require Ash.Expr

  alias Rescord.Accounts
  alias Rescord.Accounts.User
  alias Rescord.Transfers.{Checks.PowerIn, Transfer}

  @impl true
  def describe(_opts), do: "the actor is a member of an organisation of the record"

  @impl true
  def filter(%User{} = actor, %{resource: resource}, _opts) do
    ids = actor |> Accounts.organisations_for() |> Enum.map(& &1.id)

    case resource do
      Transfer ->
        deciders = Enum.filter(ids, &PowerIn.granted?(actor, &1, Transfer, :accept))

        Ash.Expr.expr(
          from_organisation_id in ^ids or
            (to_organisation_id in ^ids and state == :accepted) or
            (to_organisation_id in ^deciders and state == :sent)
        )

      Rescord.Transfers.RemotePartner ->
        Ash.Expr.expr(organisation_id in ^ids)

      _partnership ->
        Ash.Expr.expr(from_organisation_id in ^ids or to_organisation_id in ^ids)
    end
  end

  def filter(_actor, _authorizer, _opts), do: false
end
