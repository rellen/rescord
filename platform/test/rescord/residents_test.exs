defmodule Rescord.ResidentsTest do
  @moduledoc """
  Holds the residents of an organisation (`docs/domain.md`, section 5.2, and
  ADR 0025): the facts of a resident, their history, the status that Rescord
  calculates, and who can do what.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.Residents

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     lists: lists!(organisation, root),
     options: [actor: member, tenant: organisation]}
  end

  defp facts(resident, options) do
    {:ok, %Residents.Resident{} = resident} = Residents.resident_with_facts(resident.id, options)
    resident
  end

  defp count(options) do
    options |> Residents.residents!() |> length()
  end

  describe "a new resident" do
    test "has each fact that the form gave", %{lists: lists, options: options} do
      resident =
        Residents.register_resident!(
          %{
            name: "Biscuit",
            species_id: lists.species.guinea_pig,
            sex: :male,
            born_on: ~D[2025-03-01],
            born_on_estimated: true,
            size_class_id: lists.size_class.small,
            coat_id: lists.coat.rough,
            desex_status: :desexed,
            breed_ids: [lists.breed.abyssinian, lists.breed.rex],
            colour_ids: [lists.colour.white, lists.colour.tan, lists.colour.black],
            temperament_ids: [lists.temperament.confident],
            arrival_kind: :surrender,
            arrived_on: ~D[2026-09-12],
            arrival_note: "With his sister Pepper"
          },
          options
        )

      resident = facts(resident, options)

      assert resident.name == "Biscuit"
      assert resident.sex == :male
      assert resident.born_on == ~D[2025-03-01]
      assert resident.born_on_estimated
      assert resident.desex_status == :desexed
      assert resident.status == :in_care
      assert to_string(resident.species.label) == "Guinea pig"
      assert to_string(resident.size_class.label) == "Small"
      assert to_string(resident.coat.label) == "Rough"
      assert labels(resident.resident_breeds, :breed) == ["Abyssinian", "Rex"]
      assert labels(resident.resident_colours, :colour) == ["Black", "Tan", "White"]
      assert labels(resident.resident_temperaments, :temperament) == ["Confident"]
      assert resident.arrival.kind == :surrender
      assert resident.arrival.arrived_on == ~D[2026-09-12]
      assert resident.arrival.note == "With his sister Pepper"
      assert resident.departure == nil
      assert resident.absence == nil
      assert resident.identifiers == []
    end

    test "with only a species is expected, with no name, and not known to be desexed",
         %{lists: lists, options: options} do
      resident = Residents.register_resident!(%{species_id: lists.species.rabbit}, options)
      resident = facts(resident, options)

      assert resident.name == nil
      assert resident.sex == :unknown
      assert resident.desex_status == :unknown
      assert resident.status == :expected
      assert resident.arrival == nil
      assert resident.resident_breeds == []
    end

    test "needs a species", %{options: options} do
      assert {:error, %Ash.Error.Invalid{}} =
               Residents.register_resident(%{name: "Biscuit"}, options)

      assert count(options) == 0
    end

    test "has an arrival with a kind and a date, or no arrival", %{lists: lists, options: options} do
      species = %{species_id: lists.species.guinea_pig}

      assert {:error, %Ash.Error.Invalid{} = error} =
               Residents.register_resident(Map.put(species, :arrival_kind, :stray), options)

      assert Exception.message(error) =~ "is necessary with the kind of the arrival"

      assert {:error, %Ash.Error.Invalid{} = error} =
               Residents.register_resident(Map.put(species, :arrived_on, ~D[2026-09-12]), options)

      assert Exception.message(error) =~ "is necessary with the date of the arrival"
      assert count(options) == 0
    end

    test "is not there at all when one of its facts is refused", %{lists: lists, options: options} do
      # The arrival is after today in each time zone.
      late = %{arrival_kind: :stray, arrived_on: Date.add(Date.utc_today(), 2)}

      assert {:error, %Ash.Error.Invalid{} = error} =
               Residents.register_resident(
                 Map.merge(%{name: "Biscuit", species_id: lists.species.guinea_pig}, late),
                 options
               )

      assert Exception.message(error) =~ "cannot be after today"

      # The breed is not in the list of the organisation.
      assert {:error, _error} =
               Residents.register_resident(
                 %{species_id: lists.species.guinea_pig, breed_ids: [Ash.UUID.generate()]},
                 options
               )

      assert count(options) == 0
    end

    test "has its facts from the instant of the action, when the action names one",
         %{lists: lists, options: options} do
      instant = DateTime.utc_now()
      Process.sleep(5)

      resident =
        resident!(lists, [as_of: instant] ++ options, %{breed_ids: [lists.breed.rex]})

      # The name, the breed and the arrival are there at that same instant.
      then = facts(resident, [as_of: instant] ++ options)
      assert then.name == "Biscuit"
      assert then.status == :in_care
      assert labels(then.resident_breeds, :breed) == ["Rex"]
    end

    test "arrives no later than today in the time zone of its organisation", context do
      # These two zones are 26 hours apart, so the east one is always one day
      # or two ahead of the west one. The test thus needs no clock of its own.
      east = organisation!(context.root, "East", "Pacific/Kiritimati")
      west = organisation!(context.root, "West", "Etc/GMT+12")
      today_east = Rescord.Accounts.today(east)

      assert Date.compare(today_east, Rescord.Accounts.today(west)) == :gt

      for {organisation, outcome} <- [{east, :ok}, {west, :error}] do
        options = [actor: context.root, tenant: organisation]
        lists = lists!(organisation, context.root)

        result =
          Residents.register_resident(
            %{species_id: lists.species.guinea_pig, arrival_kind: :stray, arrived_on: today_east},
            options
          )

        assert elem(result, 0) == outcome
      end

      # Tomorrow is too late in each of them.
      east_options = [actor: context.root, tenant: east]
      {:ok, [species | _]} = Rescord.Lists.values(:species, east_options)

      assert {:error, %Ash.Error.Invalid{} = error} =
               Residents.register_resident(
                 %{
                   species_id: species.id,
                   arrival_kind: :stray,
                   arrived_on: Date.add(today_east, 1)
                 },
                 east_options
               )

      assert Exception.message(error) =~ "cannot be after today"
    end
  end

  describe "who can read and write a resident" do
    test "each member, each administrator and a root user", context do
      for user <- [context.member, context.administrator, context.root] do
        options = [actor: user, tenant: context.organisation]
        resident = resident!(context.lists, options)

        assert facts(resident, options).name == "Biscuit"
        assert {:ok, _} = Residents.revise_resident(resident, %{name: "Bis"}, options)
      end

      assert count(context.options) == 3
    end

    test "not a user of another organisation, and not a person who is not signed in", context do
      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)
      resident = resident!(context.lists, context.options)

      for actor <- [outsider, user!(), nil] do
        options = [actor: actor, tenant: context.organisation]

        # A read that the policy refuses is empty, and is not an error.
        assert Residents.residents!(options) == []
        assert Residents.resident!(resident.id, options) == nil
        assert Residents.name_history(resident.id, options) == []

        assert {:error, %Ash.Error.Forbidden{}} =
                 Residents.register_resident(
                   %{species_id: context.lists.species.guinea_pig},
                   options
                 )

        assert {:error, %Ash.Error.Forbidden{}} =
                 Residents.revise_resident(resident, %{name: "Mine"}, options)

        assert {:error, %Ash.Error.Forbidden{}} =
                 Residents.record_departure(
                   %{resident_id: resident.id, kind: :release, departed_on: Date.utc_today()},
                   options
                 )
      end

      # The other organisation has no resident.
      assert Residents.residents!(actor: outsider, tenant: other) == []
      assert count(context.options) == 1
      assert facts(resident, context.options).name == "Biscuit"
    end

    test "nobody writes a name, a desex status or a tie but through the resident", context do
      resident = resident!(context.lists, context.options)

      for {resource, action, input} <- [
            {Residents.ResidentName, :set, %{name: "Other"}},
            {Residents.ResidentDesexStatus, :set, %{status: :desexed}},
            {Residents.ResidentBreed, :add, %{breed_id: context.lists.breed.rex}}
          ],
          user <- [context.member, context.administrator] do
        assert {:error, %Ash.Error.Forbidden{}} =
                 resource
                 |> Ash.Changeset.for_create(action, Map.put(input, :resident_id, resident.id),
                   actor: user,
                   tenant: context.organisation
                 )
                 |> Ash.create()
      end
    end

    test "the grants name only resources and actions that exist" do
      for {_role, grants} <- Residents.Grants.grants(), {resource, action, :all} <- grants do
        assert Ash.Resource.Info.action(resource, action),
               "#{inspect(resource)} has no action #{action}"
      end

      assert Residents.role_can?(:member, :resident, :register)
      assert Residents.role_can?(:root, :departure, :withdraw)
      refute Residents.role_can?(nil, :resident, :read)
    end
  end

  describe "a change to a resident" do
    test "gives a new name, and keeps the old one for a past instant", context do
      resident = resident!(context.lists, context.options)
      before = DateTime.utc_now()

      administrator = [actor: context.administrator, tenant: context.organisation]
      assert {:ok, _} = Residents.revise_resident(resident, %{name: "Bis"}, administrator)

      assert facts(resident, context.options).name == "Bis"
      assert facts(resident, [as_of: before] ++ context.options).name == "Biscuit"

      assert [first, second] = Residents.name_history(resident.id, context.options)
      assert {first.value, first.user_id} == {"Biscuit", context.member.id}
      assert {second.value, second.user_id} == {"Bis", context.administrator.id}
      assert DateTime.compare(first.from, second.from) == :lt
    end

    test "writes no new version of a fact that did not change", context do
      resident = resident!(context.lists, context.options, %{desex_status: :entire})

      assert {:ok, _} =
               Residents.revise_resident(
                 resident,
                 %{name: "Biscuit", desex_status: :entire},
                 context.options
               )

      assert [%{value: "Biscuit"}] = Residents.name_history(resident.id, context.options)
      assert [%{value: :entire}] = Residents.desex_history(resident.id, context.options)
    end

    test "changes nothing for an argument that the form did not give", context do
      lists = context.lists

      resident =
        resident!(lists, context.options, %{
          desex_status: :entire,
          breed_ids: [lists.breed.sheltie],
          colour_ids: [lists.colour.tan]
        })

      assert {:ok, _} = Residents.revise_resident(resident, %{sex: :female}, context.options)

      resident = facts(resident, context.options)
      assert resident.sex == :female
      assert resident.name == "Biscuit"
      assert resident.desex_status == :entire
      assert labels(resident.resident_breeds, :breed) == ["Sheltie"]
      assert labels(resident.resident_colours, :colour) == ["Tan"]
    end

    test "keeps the history of the desex status", context do
      resident = resident!(context.lists, context.options)
      before = DateTime.utc_now()

      assert {:ok, _} =
               Residents.revise_resident(resident, %{desex_status: :desexed}, context.options)

      assert facts(resident, context.options).desex_status == :desexed
      assert facts(resident, [as_of: before] ++ context.options).desex_status == :unknown

      assert [%{value: :unknown}, %{value: :desexed}] =
               Residents.desex_history(resident.id, context.options)
    end

    test "replaces the breeds, and a breed can come again later", context do
      lists = context.lists
      breeds = &labels(facts(&1, &2).resident_breeds, :breed)

      resident =
        resident!(lists, context.options, %{breed_ids: [lists.breed.abyssinian, lists.breed.rex]})

      before = DateTime.utc_now()

      assert {:ok, _} =
               Residents.revise_resident(
                 resident,
                 %{breed_ids: [lists.breed.rex, lists.breed.sheltie]},
                 context.options
               )

      assert breeds.(resident, context.options) == ["Rex", "Sheltie"]
      assert breeds.(resident, [as_of: before] ++ context.options) == ["Abyssinian", "Rex"]

      assert {:ok, _} = Residents.revise_resident(resident, %{breed_ids: []}, context.options)
      assert breeds.(resident, context.options) == []

      assert {:ok, _} =
               Residents.revise_resident(
                 resident,
                 %{breed_ids: [lists.breed.abyssinian]},
                 context.options
               )

      assert breeds.(resident, context.options) == ["Abyssinian"]
    end

    test "keeps the species that the resident had at a past instant", context do
      resident = resident!(context.lists, context.options)
      before = DateTime.utc_now()

      assert {:ok, _} =
               Residents.revise_resident(
                 resident,
                 %{species_id: context.lists.species.rabbit},
                 context.options
               )

      assert to_string(facts(resident, context.options).species.label) == "Rabbit"

      assert to_string(facts(resident, [as_of: before] ++ context.options).species.label) ==
               "Guinea pig"
    end
  end

  describe "the status of a resident" do
    setup context do
      resident =
        Residents.register_resident!(
          %{name: "Caramel", species_id: context.lists.species.guinea_pig},
          context.options
        )

      {:ok, resident: resident}
    end

    defp status(resident, options), do: facts(resident, options).status

    test "follows the arrival, each absence and the departure", %{resident: resident} = context do
      options = context.options
      assert status(resident, options) == :expected

      assert {:ok, _} =
               Residents.record_arrival(
                 %{resident_id: resident.id, kind: :stray, arrived_on: Date.utc_today()},
                 options
               )

      assert status(resident, options) == :in_care

      assert {:ok, absence} =
               Residents.start_absence(
                 %{resident_id: resident.id, reason: "At the clinic"},
                 options
               )

      away = DateTime.utc_now()
      assert status(resident, options) == :away
      assert facts(resident, options).absence.reason == "At the clinic"

      assert :ok = Residents.finish_absence(absence, options)
      assert status(resident, options) == :in_care

      # At an instant in the absence, the resident was away.
      assert status(resident, [as_of: away] ++ options) == :away

      # The resident can be away again.
      assert {:ok, _} =
               Residents.start_absence(%{resident_id: resident.id, reason: "A weekend"}, options)

      assert status(resident, options) == :away

      assert {:ok, departure} =
               Residents.record_departure(
                 %{
                   resident_id: resident.id,
                   kind: :transfer_out,
                   departed_on: Date.utc_today(),
                   note: "To Banksia Road"
                 },
                 options
               )

      left = DateTime.utc_now()
      assert status(resident, options) == :left

      # A departure that was a mistake goes, and the resident is as before.
      assert :ok = Residents.withdraw_departure(departure, options)
      assert status(resident, options) == :away
      assert status(resident, [as_of: left] ++ options) == :left
    end

    test "has one arrival, one departure and one absence at a time",
         %{resident: resident} = context do
      options = context.options
      arrival = %{resident_id: resident.id, kind: :stray, arrived_on: Date.utc_today()}
      departure = %{resident_id: resident.id, kind: :release, departed_on: Date.utc_today()}
      absence = %{resident_id: resident.id, reason: "At the clinic"}

      assert {:ok, _} = Residents.record_arrival(arrival, options)
      assert {:error, %Ash.Error.Invalid{} = error} = Residents.record_arrival(arrival, options)
      assert Exception.message(error) =~ "has an arrival already"

      assert {:ok, _} = Residents.start_absence(absence, options)
      assert {:error, %Ash.Error.Invalid{} = error} = Residents.start_absence(absence, options)
      assert Exception.message(error) =~ "is away already"

      assert {:ok, _} = Residents.record_departure(departure, options)

      assert {:error, %Ash.Error.Invalid{} = error} =
               Residents.record_departure(departure, options)

      assert Exception.message(error) =~ "has a departure already"
    end

    test "has no arrival and no departure after today", %{resident: resident} = context do
      late = Date.add(Date.utc_today(), 2)

      assert {:error, %Ash.Error.Invalid{}} =
               Residents.record_arrival(
                 %{resident_id: resident.id, kind: :stray, arrived_on: late},
                 context.options
               )

      assert {:error, %Ash.Error.Invalid{}} =
               Residents.record_departure(
                 %{resident_id: resident.id, kind: :release, departed_on: late},
                 context.options
               )

      assert status(resident, context.options) == :expected
    end

    test "corrects an arrival, and keeps what it said before", %{resident: resident} = context do
      {:ok, arrival} =
        Residents.record_arrival(
          %{resident_id: resident.id, kind: :stray, arrived_on: ~D[2026-10-25]},
          context.options
        )

      before = DateTime.utc_now()

      assert {:ok, _} =
               Residents.correct_arrival(
                 arrival,
                 %{kind: :surrender, note: "By the owner"},
                 context.options
               )

      assert facts(resident, context.options).arrival.kind == :surrender
      assert facts(resident, [as_of: before] ++ context.options).arrival.kind == :stray
    end

    test "is a filter and the name is a sort of a list of residents", context do
      lists = context.lists
      resident!(lists, context.options, %{name: "Sorrel"})
      resident!(lists, context.options, %{name: "Acorn"})

      residents =
        Residents.residents!(
          [query: [filter: [status: :in_care], sort: [name: :asc]], load: Residents.summary()] ++
            context.options
        )

      assert Enum.map(residents, & &1.name) == ["Acorn", "Sorrel"]
      assert Enum.all?(residents, &(&1.status == :in_care))
      assert Enum.all?(residents, &(to_string(&1.species_label) == "Guinea pig"))

      assert [%{name: "Caramel"}] =
               Residents.residents!(
                 [query: [filter: [status: :expected]], load: [:name]] ++ context.options
               )
    end
  end

  describe "a resident that was recorded by mistake" do
    test "goes when an administrator removes it, and its history stays", context do
      resident = resident!(context.lists, context.options)
      other = resident!(context.lists, context.options, %{name: "Pepper"})
      before = DateTime.utc_now()

      administrator = [actor: context.administrator, tenant: context.organisation]
      assert :ok = Residents.remove_resident(resident, administrator)

      assert Residents.resident!(resident.id, context.options) == nil
      assert [%{id: id}] = Residents.residents!(context.options)
      assert id == other.id

      # At the instant before, the resident was there with its facts.
      assert facts(resident, [as_of: before] ++ context.options).name == "Biscuit"
    end

    test "does not go for a member, and goes for a root user", context do
      resident = resident!(context.lists, context.options)

      assert {:error, %Ash.Error.Forbidden{}} =
               Residents.remove_resident(resident, context.options)

      assert count(context.options) == 1
      refute Residents.role_can?(:member, :resident, :remove)
      assert Residents.role_can?(:administrator, :resident, :remove)

      assert :ok =
               Residents.remove_resident(resident,
                 actor: context.root,
                 tenant: context.organisation
               )

      assert count(context.options) == 0
    end

    test "keeps a value that its organisation retired", context do
      lists = context.lists
      resident = resident!(lists, context.options, %{breed_ids: [lists.breed.rex]})

      {:ok, _} =
        Rescord.Lists.retire_value(:breed, lists.breed.rex,
          actor: context.administrator,
          tenant: context.organisation
        )

      assert labels(facts(resident, context.options).resident_breeds, :breed) == ["Rex"]
    end
  end

  describe "an identifier" do
    test "has a kind of the list of the organisation, and its removal names who did it",
         context do
      resident = resident!(context.lists, context.options)

      assert {:ok, identifier} =
               Residents.add_identifier(
                 %{
                   resident_id: resident.id,
                   kind_id: context.lists.identifier_kind.microchip,
                   value: "956000012345678"
                 },
                 context.options
               )

      assert [%{value: "956000012345678", kind: kind}] =
               facts(resident, context.options).identifiers

      assert to_string(kind.label) == "Microchip"

      before = DateTime.utc_now()
      administrator = [actor: context.administrator, tenant: context.organisation]
      assert :ok = Residents.remove_identifier(identifier, administrator)

      assert facts(resident, context.options).identifiers == []

      assert [%{value: "956000012345678"}] =
               facts(resident, [as_of: before] ++ context.options).identifiers

      version = AshPaperTrail.Resource.Info.version_resource(Residents.ResidentIdentifier)

      versions =
        version
        |> Ash.read!(tenant: context.organisation, authorize?: false)
        |> Enum.sort_by(& &1.valid_at.lower, DateTime)

      assert Enum.map(versions, &{&1.version_action_name, &1.user_id}) ==
               [{:add, context.member.id}, {:remove, context.administrator.id}]
    end
  end
end
