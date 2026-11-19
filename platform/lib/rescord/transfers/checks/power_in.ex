defmodule Rescord.Transfers.Checks.PowerIn do
  @moduledoc """
  A policy check for a partnership or a transfer (ADR 0042): the role of
  the actor in one of its two organisations has a grant for the action.

  A partnership and a transfer are outside the schemas of the
  organisations, so a request for one has no tenant, and
  `Rescord.Accounts.Checks.Granted` cannot find the role. This check reads
  the member of the actor in the organisation that the option `side`
  names:

    * `:from` - the organisation that asked, or that sends;
    * `:to` - the organisation that answers, or that receives;
    * `:either` - one of the two;
    * `:own` - the refuge of a record that belongs to one refuge, such as
      a partner on another server.
  """

  use Ash.Policy.SimpleCheck

  alias Rescord.Accounts
  alias Rescord.Accounts.{Checks.Granted, Grants, User}

  @impl true
  def describe(opts), do: "the role of the actor in the #{opts[:side]} organisation has a grant"

  @impl true
  def match?(%User{} = actor, %{changeset: %Ash.Changeset{} = changeset}, opts) do
    ids =
      case opts[:side] do
        :from ->
          [attribute(changeset, :from_organisation_id)]

        :to ->
          [attribute(changeset, :to_organisation_id)]

        :own ->
          [attribute(changeset, :organisation_id)]

        :either ->
          [:from_organisation_id, :to_organisation_id] |> Enum.map(&attribute(changeset, &1))
      end

    Enum.any?(ids, &granted?(actor, &1, changeset.resource, changeset.action.name))
  end

  def match?(_actor, _context, _opts), do: false

  defp attribute(changeset, name), do: Ash.Changeset.get_attribute(changeset, name)

  @doc """
  Whether the role of `actor` in the organisation with the id
  `organisation_id` has a grant for `action` of `resource`.
  """
  def granted?(%User{root?: true}, _organisation_id, _resource, _action), do: true

  def granted?(%User{} = actor, organisation_id, resource, action)
      when is_binary(organisation_id) do
    case Ash.get(Accounts.Organisation, organisation_id,
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok, %{} = organisation} ->
        role = Granted.role_of(actor, organisation)
        Grants.scope(role, resource, action) != :none

      _none ->
        false
    end
  end

  def granted?(_actor, _organisation_id, _resource, _action), do: false
end
