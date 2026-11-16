defmodule Rescord.Residents do
  @moduledoc """
  The residents of an organisation: the animals in its care, with their
  arrival and their departure (`docs/domain.md`, section 5.2).

  Each resource here is in the schema of the organisation and is temporal
  (ADR 0012). Pass `as_of:` in the options of a function to read the
  residents as they were at a past instant.

  `Rescord.Residents.Resident` says how the resources fit together.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  require Ash.Query

  alias Rescord.Residents.{
    Absence,
    Arrival,
    Departure,
    Resident,
    ResidentDesexStatus,
    ResidentIdentifier,
    ResidentName
  }

  boundary do
    deps [Rescord, Rescord.Accounts, Rescord.Lists]
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Rescord.Residents.Resident do
      define :residents, action: :read
      define :resident, action: :read, get_by: [:id], not_found_error?: false
      define :register_resident, action: :register
      define :revise_resident, action: :revise
      define :remove_resident, action: :remove
    end

    resource Rescord.Residents.ResidentName
    resource Rescord.Residents.ResidentDesexStatus
    resource Rescord.Residents.ResidentBreed
    resource Rescord.Residents.ResidentColour
    resource Rescord.Residents.ResidentTemperament

    resource Rescord.Residents.ResidentIdentifier do
      define :add_identifier, action: :add
      define :remove_identifier, action: :remove
    end

    resource Rescord.Residents.Arrival do
      define :record_arrival, action: :record
      define :correct_arrival, action: :correct
    end

    resource Rescord.Residents.Departure do
      define :record_departure, action: :record
      define :correct_departure, action: :correct
      define :withdraw_departure, action: :withdraw
    end

    resource Rescord.Residents.Absence do
      define :start_absence, action: :start
      define :finish_absence, action: :finish
    end
  end

  # Each fact that the page of one resident shows.
  @facts [
    :name,
    :status,
    :desex_status,
    :arrival,
    :departure,
    :absence,
    species: [:label],
    size_class: [:label],
    coat: [:label],
    resident_breeds: [breed: [:label]],
    resident_colours: [colour: [:label]],
    resident_temperaments: [temperament: [:label]],
    identifiers: [kind: [:label]]
  ]

  @doc "What a list of residents loads for each one: the name, the species and the status."
  def summary, do: [:name, :species_label, :status, :arrived_on]

  @doc """
  One resident with each of its facts, or `nil` when the actor can read no
  such resident.
  """
  def resident_with_facts(id, opts \\ []) do
    resident(id, Keyword.put(opts, :load, @facts))
  end

  @doc """
  The names that a resident had, from the first to the last. Each has the
  name, the instant from which it was valid, and the user who gave it.

  Returns `[]` when the actor can read no such resident.
  """
  def name_history(resident_id, opts \\ []), do: history(ResidentName, :name, resident_id, opts)

  @doc "The desex statuses that a resident had, as `name_history/2` gives the names."
  def desex_history(resident_id, opts \\ []),
    do: history(ResidentDesexStatus, :status, resident_id, opts)

  defp history(resource, attribute, resident_id, opts) do
    # The versions have no policy of their own: the resident decides.
    case resident(resident_id, opts) do
      {:ok, %Resident{}} ->
        resource
        |> AshPaperTrail.Resource.Info.version_resource()
        |> Ash.Query.filter(resident_id == ^resident_id)
        |> Ash.read!(tenant: opts[:tenant], authorize?: false)
        |> Enum.sort_by(& &1.valid_at.lower, DateTime)
        |> Enum.map(
          &%{value: Map.fetch!(&1, attribute), from: &1.valid_at.lower, user_id: &1.user_id}
        )

      _no_resident ->
        []
    end
  end

  @doc """
  Whether a role can run an action of a resource of this domain at all. A
  page asks this to decide what to show. The policy decides when the action
  runs.
  """
  @spec role_can?(atom | nil, :resident | :arrival | :departure | :absence | :identifier, atom) ::
          boolean
  def role_can?(role, subject, action) do
    resource =
      case subject do
        :resident -> Resident
        :arrival -> Arrival
        :departure -> Departure
        :absence -> Absence
        :identifier -> ResidentIdentifier
      end

    Rescord.Accounts.granted?(role, resource, action)
  end
end
