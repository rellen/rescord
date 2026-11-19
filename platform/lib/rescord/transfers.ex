defmodule Rescord.Transfers do
  @moduledoc """
  The transfers of residents between partner refuges (`docs/domain.md`,
  section 4, and ADR 0042).

  A refuge asks another refuge, by its short name, to be a partner
  (`ask_partner/3`), and the two are partners when the other refuge
  accepts. A refuge then sends a partner a copy of a resident
  (`send_transfer/2`): its facts, its medical history, and the parts that
  the sender chooses. The partner accepts the transfer, and each of its
  members then reads the copy, or it declines it.

  A partnership and a transfer are outside the schemas of the
  organisations. Their policies read the role of the actor in each of the
  two organisations (`Rescord.Transfers.Checks.PowerIn`), and the power is
  `:transfers`.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  require Ash.Query

  alias Rescord.Transfers.{Partnership, Snapshot, Transfer}

  boundary do
    deps [Rescord, Rescord.Accounts, Rescord.Residents, Rescord.Journal, Rescord.Locations]
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Partnership do
      define :partnerships, action: :read
      define :partnership, action: :read, get_by: [:id], not_found_error?: false
      define :accept_partner, action: :accept
      define :decline_partner, action: :decline
      define :end_partnership, action: :end
    end

    resource Transfer do
      define :transfers, action: :read
      define :transfer, action: :read, get_by: [:id], not_found_error?: false
      define :send_transfer, action: :send
      define :accept_transfer, action: :accept
      define :decline_transfer, action: :decline
      define :withdraw_transfer, action: :withdraw
    end
  end

  @doc """
  Asks the refuge with the short name `short_name` to be a partner of the
  refuge `organisation`.
  """
  def ask_partner(organisation, short_name, opts \\ []) do
    Partnership
    |> Ash.Changeset.for_create(
      :ask,
      %{organisation_id: organisation.id, short_name: short_name},
      opts
    )
    |> Ash.create()
  end

  @doc """
  The partnerships of an organisation that the actor can read, each with
  its two organisations, the newest first.
  """
  def partnerships_of(organisation, opts \\ []) do
    id = organisation.id

    Partnership
    |> Ash.Query.filter(from_organisation_id == ^id or to_organisation_id == ^id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read(opts)
    |> with_organisations()
  end

  @doc """
  The refuges that are accepted partners of an organisation, as
  `{name, id}`, in the order of the names.
  """
  def partners_of(organisation, opts \\ []) do
    with {:ok, partnerships} <- partnerships_of(organisation, opts) do
      {:ok,
       for(
         %{state: :accepted} = partnership <- partnerships,
         other = other(partnership, organisation),
         do: {other.name, other.id}
       )
       |> Enum.sort()}
    end
  end

  @doc "The other organisation of a partnership or a transfer."
  def other(%{from_organisation_id: id} = record, %{id: id}), do: record.to_organisation
  def other(record, _organisation), do: record.from_organisation

  @doc """
  The transfers of an organisation that the actor can read, each with its
  two organisations, the newest first. The copy is not loaded: a list does
  not need it.
  """
  def transfers_of(organisation, opts \\ []) do
    id = organisation.id

    Transfer
    |> Ash.Query.filter(from_organisation_id == ^id or to_organisation_id == ^id)
    |> Ash.Query.deselect([:snapshot])
    |> Ash.Query.sort(sent_at: :desc)
    |> Ash.read(opts)
    |> with_organisations()
  end

  @doc """
  One transfer of an organisation with its copy, or `nil` when the actor
  can read no such transfer of that organisation.
  """
  def transfer_of(organisation, id, opts \\ []) do
    organisation_id = organisation.id

    Transfer
    |> Ash.Query.filter(
      id == ^id and
        (from_organisation_id == ^organisation_id or to_organisation_id == ^organisation_id)
    )
    |> Ash.read_one(opts)
    |> with_organisations()
  end

  # The two organisations of each record that the actor read. Only a root
  # user reads an organisation through its actions, and a person who reads
  # a partnership or a transfer reads the names of its two refuges.
  defp with_organisations({:ok, nil}), do: {:ok, nil}

  defp with_organisations({:ok, records}),
    do: Ash.load(records, [:from_organisation, :to_organisation], authorize?: false)

  defp with_organisations({:error, error}), do: {:error, error}

  @doc "The parts that a sender can add to the facts and the medical history."
  defdelegate parts(), to: Snapshot

  @doc """
  Whether a role can run an action of a partnership or a transfer at all. A
  page asks this to decide what to show. The policy decides when the action
  runs.
  """
  @spec role_can?(term, :partnership | :transfer, atom) :: boolean
  def role_can?(role, subject, action) do
    resource = if subject == :partnership, do: Partnership, else: Transfer
    Rescord.Accounts.granted?(role, resource, action)
  end
end
