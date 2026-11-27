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

  alias Rescord.Transfers.{Archive, Keys, Partnership, RemotePartner, Snapshot, Transfer}

  boundary do
    deps [
      Rescord,
      Rescord.Accounts,
      Rescord.Residents,
      Rescord.Journal,
      Rescord.Locations,
      Rescord.Photos
    ]
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

    resource RemotePartner do
      define :end_remote_partner, action: :end
    end

    resource Rescord.Transfers.RefugeKey
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
  def other(%{from_organisation_id: id} = record, %{id: id}),
    do: record.to_organisation || record.remote_partner

  def other(record, _organisation), do: record.from_organisation || record.remote_partner

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
    |> with_organisations([:remote_partner])
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
    |> with_organisations([:remote_partner])
  end

  # The two organisations of each record that the actor read. Only a root
  # user reads an organisation through its actions, and a person who reads
  # a partnership or a transfer reads the names of its two refuges.
  # A transfer also loads its partner on another server.
  defp with_organisations(result, more \\ [])
  defp with_organisations({:ok, nil}, _more), do: {:ok, nil}

  defp with_organisations({:ok, records}, more),
    do: Ash.load(records, [:from_organisation, :to_organisation] ++ more, authorize?: false)

  defp with_organisations({:error, error}, _more), do: {:error, error}

  @doc """
  Writes a transfer file of a resident for a partner on another server
  (ADR 0043). Returns the record of the export and the bytes of the file.
  """
  def export_transfer(facts, opts \\ []) do
    Transfer
    |> Ash.Changeset.for_create(:export, facts, opts)
    |> Ash.create()
    |> case do
      {:ok, transfer} -> {:ok, transfer, transfer.__metadata__.file}
      {:error, error} -> {:error, error}
    end
  end

  @doc "Reads a transfer file from a partner on another server into the refuge `organisation`."
  def import_transfer(organisation, file, opts \\ []) do
    Transfer
    |> Ash.Changeset.for_create(:import, %{organisation_id: organisation.id, file: file}, opts)
    |> Ash.create()
  end

  @doc "Records a partner on another server from its partner card."
  def record_remote_partner(organisation, card, opts \\ []) do
    RemotePartner
    |> Ash.Changeset.for_create(:record, %{organisation_id: organisation.id, card: card}, opts)
    |> Ash.create()
  end

  @doc "The partners of an organisation on other servers, the newest first."
  def remote_partners_of(organisation, opts \\ []) do
    id = organisation.id

    RemotePartner
    |> Ash.Query.filter(organisation_id == ^id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read(opts)
  end

  @doc "The partner card of a refuge, and the fingerprint of its keys (ADR 0043)."
  def card(organisation), do: {Keys.card(organisation), Keys.fingerprint(organisation)}

  @doc """
  A file of the copy of a transfer, and its bytes, when the actor can read
  the transfer of the organisation and its copy names the file. A file of
  an export is not kept on this server.
  """
  def transfer_file(organisation, id, file_id, opts \\ []) do
    with {:ok, %{to_organisation_id: to_id} = transfer} when is_binary(to_id) <-
           transfer_of(organisation, id, opts),
         %{} = file <- Rescord.Transfers.Files.named(transfer.snapshot, file_id),
         {:ok, bytes} <-
           Rescord.Storage.get(Rescord.Transfers.Files.key(to_id, transfer.id, file["id"])) do
      {:ok, file, bytes}
    else
      _no_file -> {:error, :not_found}
    end
  end

  @doc "The largest transfer file that an import takes, in bytes."
  defdelegate max_file_size(), to: Archive, as: :max_size

  @doc "The parts that a sender can add to the facts and the medical history."
  defdelegate parts(), to: Snapshot

  @doc """
  Whether a role can run an action of a partnership or a transfer at all. A
  page asks this to decide what to show. The policy decides when the action
  runs.
  """
  @spec role_can?(term, :partnership | :transfer | :remote_partner, atom) :: boolean
  def role_can?(role, subject, action) do
    resource =
      case subject do
        :partnership -> Partnership
        :transfer -> Transfer
        :remote_partner -> RemotePartner
      end

    Rescord.Accounts.granted?(role, resource, action)
  end
end
