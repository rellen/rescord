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
    extensions: [AshBoundary, AshPaperTrail.Domain, AshAi]

  require Ash.Query

  alias Rescord.Residents.{
    Absence,
    Arrival,
    Departure,
    Family,
    FamilyMember,
    Group,
    GroupMember,
    Kinship,
    ParentLink,
    Resident,
    ResidentDesexStatus,
    ResidentIdentifier,
    ResidentName
  }

  boundary do
    # A relationship and a signal listener are checked too (ADR 0066).
    check aliases: true
    deps [Rescord, Rescord.Accounts, Rescord.Lists]
    # The domains that listen name the signals (ADR 0067).
    exports [Rescord.Residents.Signals]
  end

  paper_trail do
    include_versions? true
  end

  # The tools of the assistant (ADR 0069). A tool here does not exist for
  # Ruby until `Rescord.Ruby.Catalogue` names it, and it runs as the
  # member, with the policy of the action.
  tools do
    tool :find_residents, Rescord.Residents.Resident, :read do
      description """
      Finds residents (the animals of the rescue) by name, status, species or sex.
      Use it to turn a name that the person said into a resident. A missing
      field means that nothing is recorded.
      """

      load [:name, :status, :species_label, :arrived_on]
      select [:id, :sex]
      filterable_fields([:name, :status, :species_label, :sex])
      sortable_fields([:name, :arrived_on])
      aggregatable_fields([])
      action_parameters([:filter, :sort, :limit, :result_type])
      annotations(read_only_hint: true)
    end
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

    resource Rescord.Residents.ParentLink do
      define :record_parent, action: :record
      define :remove_parent, action: :remove
    end

    resource Rescord.Residents.Family do
      define :families, action: :read
      define :name_family, action: :name, args: [:name]
      define :rename_family, action: :rename, args: [:name]
    end

    resource Rescord.Residents.FamilyMember do
      define :add_to_family, action: :add
      define :remove_from_family, action: :remove
    end

    resource Rescord.Residents.Group do
      define :groups, action: :read
      define :group, action: :read, get_by: [:id], not_found_error?: false
      define :form_group, action: :form
      define :revise_group, action: :revise
      define :close_group, action: :close
    end

    resource Rescord.Residents.GroupMember do
      define :join_group, action: :join
      define :leave_group, action: :leave
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

  @doc """
  The changes that Rescord recorded about a resident, in the order of time:
  its name, its arrival, its departure, each absence and each group. Each
  one is a change of `Rescord.History` with a `subject`: `:name`,
  `:arrival`, `:departure`, `:absence` or `:group_member`.

  Returns `[]` when the actor can read no such resident: the policy of the
  versions refuses each actor (ADR 0063), so the resident decides.
  """
  def changes(resident_id, opts \\ []) do
    subjects = [
      name: ResidentName,
      arrival: Arrival,
      departure: Departure,
      absence: Absence,
      group_member: GroupMember
    ]

    case resident(resident_id, opts) do
      {:ok, %Resident{}} ->
        for {subject, resource} <- subjects,
            change <-
              resource
              |> AshPaperTrail.Resource.Info.version_resource()
              |> Ash.Query.filter(resident_id == ^resident_id)
              |> Ash.read!(tenant: opts[:tenant], authorize?: false)
              |> Rescord.History.changes() do
          Map.put(change, :subject, subject)
        end
        |> Enum.sort_by(& &1.at, DateTime)

      _no_resident ->
        []
    end
  end

  @doc """
  The residents that need somebody now (ADR 0065): each resident that is
  away and whose day to be back is before today, the one that is the most
  late first, and then each resident that is expected, in the order of the
  names.

  Returns `%{rows: rows, total: total}`. A row is
  `%{kind: :late_back, record: resident, absence: absence}` or
  `%{kind: :expected, record: resident}`, each resident with its name. There
  are at most `:limit` rows, and `total` counts each such resident. A row
  is there only for a role that can do something about it: say that the
  resident is back, or record the arrival.
  """
  @spec attention(term, keyword) :: {:ok, %{rows: [map], total: non_neg_integer}} | {:error, term}
  def attention(role, opts \\ []) do
    {now, opts} = Keyword.pop(opts, :now, DateTime.utc_now())
    {limit, opts} = Keyword.pop(opts, :limit, 8)
    today = Rescord.Accounts.local_date(opts[:tenant], now)

    with {:ok, late} <- late_back(role_can?(role, :absence, :finish), today, limit, opts),
         {:ok, expected} <- expected(role_can?(role, :arrival, :record), limit, opts) do
      {:ok,
       %{
         rows: Enum.take(late.rows ++ expected.rows, limit),
         total: late.total + expected.total
       }}
    end
  end

  defp late_back(false, _today, _limit, _opts), do: {:ok, %{rows: [], total: 0}}

  defp late_back(true, today, limit, opts) do
    # A resident that left is not away, whatever its absence says.
    query = Ash.Query.filter(Absence, expected_back_on < ^today and resident.status == :away)

    with {:ok, total} <- Ash.count(query, opts),
         {:ok, absences} <-
           query
           |> Ash.Query.sort(expected_back_on: :asc, id: :asc)
           |> Ash.Query.limit(limit)
           |> Ash.Query.load(resident: [:name])
           |> Ash.read(opts) do
      rows =
        for absence <- absences,
            do: %{kind: :late_back, record: absence.resident, absence: absence}

      {:ok, %{rows: rows, total: total}}
    end
  end

  defp expected(false, _limit, _opts), do: {:ok, %{rows: [], total: 0}}

  defp expected(true, limit, opts) do
    query = Ash.Query.filter(Resident, status == :expected)

    with {:ok, total} <- Ash.count(query, opts),
         {:ok, residents} <-
           query
           |> Ash.Query.sort(name: :asc, id: :asc)
           |> Ash.Query.limit(limit)
           |> Ash.Query.load(:name)
           |> Ash.read(opts) do
      {:ok, %{rows: Enum.map(residents, &%{kind: :expected, record: &1}), total: total}}
    end
  end

  @doc """
  The days of a calendar (ADR 0074): each resident that is away with a day
  on which it is expected back, from the day `:from` of `opts`, in the
  order of the days, `:limit` of them at most.

  Returns an entry for each: `%{kind: :return, record: resident, absence:
  absence, on: day}`. A resident that left is not away, whatever its
  absence says.
  """
  @spec calendar(keyword) :: {:ok, [map]} | {:error, term}
  def calendar(opts) do
    {from, opts} = Keyword.pop!(opts, :from)
    {limit, opts} = Keyword.pop(opts, :limit, 2_000)

    with {:ok, absences} <-
           Absence
           |> Ash.Query.filter(expected_back_on >= ^from and resident.status == :away)
           |> Ash.Query.sort(expected_back_on: :asc, id: :asc)
           |> Ash.Query.limit(limit)
           |> Ash.Query.load(resident: [:name])
           |> Ash.read(opts) do
      {:ok,
       for absence <- absences do
         %{
           kind: :return,
           record: absence.resident,
           absence: absence,
           on: absence.expected_back_on
         }
       end}
    end
  end

  defp history(resource, attribute, resident_id, opts) do
    # The policy of the versions refuses each actor: the resident decides.
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

  # What a page shows of a member of a group, or of a relative.
  @resident_summary [resident: [:name]]

  @doc """
  One group with its kind, its members, and `words`: how its members are
  related. The words are those of a member when the group has a
  description, and in each other case the ones that Rescord calculates.

  Returns `{:ok, nil}` when the actor can read no such group.
  """
  def group_with_facts(id, opts \\ []) do
    with {:ok, %Group{} = group} <-
           group(id, Keyword.put(opts, :load, kind: [:label], members: @resident_summary)) do
      {:ok, with_words(group, opts)}
    end
  end

  @doc "Each group of the organisation, as `group_with_facts/2` gives one."
  def groups_with_facts(opts \\ []) do
    with {:ok, groups} <-
           groups(Keyword.put(opts, :load, kind: [:label], members: @resident_summary)) do
      {:ok, Enum.map(groups, &with_words(&1, opts))}
    end
  end

  defp with_words(group, opts) do
    members = Enum.sort_by(group.members, &(&1.resident.name || ""))
    words = group.description || kinship_words(Enum.map(members, & &1.resident), opts)

    group
    |> Map.put(:members, members)
    |> Ash.Resource.put_metadata(:words, words)
  end

  @doc "The words of a group that `group_with_facts/2` loaded, or `nil`."
  def words(%Group{} = group), do: Ash.Resource.get_metadata(group, :words)

  @doc """
  A name for a group with its members and their names loaded: its own name,
  or the names of its members in the order of the names. The order does not
  depend on the order of the read.
  """
  def group_name(%Group{name: name}) when is_binary(name), do: name

  def group_name(%Group{members: members}) do
    names =
      members
      |> Enum.sort_by(&(&1.resident.name || ""))
      |> Enum.map(&(&1.resident.name || "a resident with no name"))

    case names do
      [] -> "A group with no members"
      [one] -> one
      names -> Enum.join(Enum.drop(names, -1), ", ") <> " and " <> List.last(names)
    end
  end

  # The facts are those of the policy of the group: the function reads the
  # links and the families of its members with no second decision.
  defp kinship_words(residents, opts) do
    ids = Enum.map(residents, & &1.id)
    internal = [tenant: opts[:tenant], authorize?: false] ++ Keyword.take(opts, [:as_of])

    links =
      ParentLink
      |> Ash.Query.filter(resident_id in ^ids)
      |> Ash.read!(internal)
      |> Enum.map(&%{child_id: &1.resident_id, parent_id: &1.parent_id, role: &1.role})

    families =
      FamilyMember
      |> Ash.Query.filter(resident_id in ^ids)
      |> Ash.read!(internal)
      |> Enum.group_by(& &1.resident_id, & &1.family_id)

    Kinship.describe(Enum.map(residents, &%{id: &1.id, sex: &1.sex}), links, families)
  end

  @doc """
  The relatives of a resident, and what it belongs to: its parents and its
  young, each with the resident and the role, its families, and its groups.

  Returns `nil` when the actor can read no such resident.
  """
  def relations(resident_id, opts \\ []) do
    load = [
      parent_links: [parent: [:name]],
      young_links: @resident_summary,
      family_memberships: [:family],
      group_memberships: []
    ]

    case resident(resident_id, Keyword.put(opts, :load, load)) do
      {:ok, %Resident{} = resident} ->
        groups =
          for membership <- resident.group_memberships,
              {:ok, %Group{} = group} <- [group_with_facts(membership.group_id, opts)] do
            {membership, group}
          end

        %{
          # The mother is first.
          parents: Enum.sort_by(resident.parent_links, &(&1.role == :father)),
          young: Enum.sort_by(resident.young_links, &(&1.resident.name || "")),
          families: Enum.sort_by(resident.family_memberships, & &1.family.name),
          groups: groups
        }

      _no_resident ->
        nil
    end
  end

  @doc """
  Whether a role can run an action of a resource of this domain at all. A
  page asks this to decide what to show. The policy decides when the action
  runs.
  """
  @spec role_can?(atom | nil, atom, atom) :: boolean
  def role_can?(role, subject, action) do
    resource =
      case subject do
        :resident -> Resident
        :arrival -> Arrival
        :departure -> Departure
        :absence -> Absence
        :identifier -> ResidentIdentifier
        :parent -> ParentLink
        :family -> Family
        :family_member -> FamilyMember
        :group -> Group
        :group_member -> GroupMember
      end

    Rescord.Accounts.granted?(role, resource, action)
  end
end
