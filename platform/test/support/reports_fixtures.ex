defmodule Rescord.ReportsFixtures do
  @moduledoc """
  A refuge with enough records for each report (ADR 0076): residents with
  their facts, a family, a group, housing, a journal, photos, tasks, a
  routine and stock. The tests of the reports read it, and so does a person
  who wants to look at the documents.

  The store of the files must be there first: see
  `Rescord.StorageFixtures.disk_store!/1`.
  """

  # Test support may use any boundary, and any test may use it (ADR 0009).
  use Boundary, top_level?: true, check: [in: false, out: false]

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{
    Accounts,
    Expenses,
    Inventory,
    Journal,
    Lists,
    Locations,
    Photos,
    Residents,
    Tasks
  }

  @doc """
  Makes the refuge Wattle Creek, and returns what a test needs of it: the
  organisation, its people, the options of a member and of an administrator,
  the lists, the day of today there, and the residents and the locations by
  their names.

  The refuge names its tax GST, and has five expenses of the last ten days:
  one that the organisation owes to the member, one that waits, one that an
  administrator declined, one that the organisation paid, and one that it
  paid back to the administrator. The first and the fourth hold the GST in
  their amounts.

  `picture` makes the bytes of a photo from the name of a resident and a
  number. It makes a plain photo of `Rescord.StorageFixtures` at first.
  """
  def refuge!(picture \\ fn _name, _number -> Rescord.StorageFixtures.photo() end) do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root, "ada@example.org")

    # The refuge names its tax, so an expense can hold the tax in its amount.
    organisation =
      Accounts.set_organisation_tax_name!(organisation, "GST", actor: administrator)

    {_, member} = member!(organisation, :member, administrator, "mel@example.org")
    lists = lists!(organisation, root)
    admin = [actor: administrator, tenant: organisation]
    options = [actor: member, tenant: organisation]
    today = Accounts.today(organisation)

    kinds =
      for {key, names} <- [location_kind: ["Building", "Pen"], group_kind: ["Bonded pair"]],
          name <- names,
          into: %{} do
        {:ok, value} = Lists.add_local_value(key, name, admin)
        {name, value.id}
      end

    locations = locations!(kinds, admin)
    residents = residents!(lists, locations, kinds, today, options)

    context = %{
      root: root,
      organisation: organisation,
      administrator: administrator,
      member: member,
      lists: lists,
      admin: admin,
      options: options,
      today: today,
      locations: locations,
      residents: residents
    }

    journal!(context)
    photos!(context, picture)
    tasks!(context)
    stock!(context)
    expenses!(context)
    context
  end

  defp locations!(kinds, admin) do
    add = fn name, kind, capacity, parent ->
      %{name: name, kind_id: kinds[kind], capacity: capacity, parent_id: parent && parent.id}
      |> Locations.add_location!(admin)
    end

    shed = add.("Main shed", "Building", 12, nil)
    cottage = add.("Quarantine cottage", "Building", nil, nil)

    %{
      shed: shed,
      cottage: cottage,
      pen_1: add.("Pen 1", "Pen", 2, shed),
      pen_2: add.("Pen 2", "Pen", 2, shed),
      pen_3: add.("Pen 3", "Pen", 4, shed),
      isolation: add.("Isolation room", "Pen", 1, cottage)
    }
  end

  defp residents!(lists, locations, kinds, today, options) do
    ago = &Date.add(today, -&1)

    biscuit =
      resident!(lists, options, %{
        name: "Biscuit",
        desex_status: :desexed,
        born_on: ago.(610),
        born_on_estimated: true,
        size_class_id: lists.size_class.small,
        coat_id: lists.coat.rough,
        markings: "Torn left ear",
        breed_ids: [lists.breed.abyssinian],
        colour_ids: [lists.colour.tan, lists.colour.white],
        temperament_ids: [lists.temperament.shy],
        arrived_on: ago.(64),
        arrival_note: "The owner moved to a home that takes no pets."
      })

    pepper =
      resident!(lists, options, %{
        name: "Pepper",
        sex: :female,
        desex_status: :entire,
        born_on: ago.(400),
        breed_ids: [lists.breed.sheltie],
        colour_ids: [lists.colour.black],
        temperament_ids: [lists.temperament.confident],
        arrived_on: ago.(64)
      })

    hazel =
      resident!(lists, options, %{
        name: "Hazel",
        sex: :female,
        born_on: ago.(520),
        breed_ids: [lists.breed.abyssinian],
        colour_ids: [lists.colour.tan],
        arrival_kind: :stray,
        arrived_on: ago.(41),
        arrival_note: "Found in a garden on the river road."
      })

    young =
      for name <- ["Pip", "Squeak"] do
        resident!(lists, options, %{
          name: name,
          sex: :unknown,
          born_on: ago.(12),
          colour_ids: [lists.colour.tan, lists.colour.white],
          arrival_kind: :born_in_care,
          arrived_on: ago.(12)
        })
      end

    clover =
      resident!(lists, options, %{
        name: "Clover",
        species_id: lists.species.rabbit,
        sex: :female,
        desex_status: :desexed,
        born_on: ago.(900),
        breed_ids: [lists.breed.rex],
        colour_ids: [lists.colour.white],
        arrival_kind: :seizure,
        arrived_on: ago.(20)
      })

    juniper =
      resident!(lists, options, %{
        name: "Juniper",
        species_id: lists.species.rabbit,
        sex: :male,
        arrival_kind: :stray,
        arrived_on: ago.(9)
      })

    maple = resident!(lists, options, %{name: "Maple", sex: :female, arrived_on: ago.(80)})
    sorrel = resident!(lists, options, %{name: "Sorrel", arrival_kind: nil, arrived_on: nil})

    for {resident, value} <- [{biscuit, "956000012345678"}, {clover, "956000087654321"}] do
      Residents.add_identifier!(
        %{resident_id: resident.id, kind_id: lists.identifier_kind.microchip, value: value},
        options
      )
    end

    Residents.add_identifier!(
      %{resident_id: biscuit.id, kind_id: lists.identifier_kind.ear_tag, value: "WC-041"},
      options
    )

    Residents.start_absence!(
      %{resident_id: juniper.id, reason: "At the vet for a dental", expected_back_on: ago.(-2)},
      options
    )

    Residents.record_departure!(
      %{
        resident_id: maple.id,
        kind: :transfer_out,
        departed_on: ago.(6),
        note: "To the refuge at Banksia Rise."
      },
      options
    )

    {:ok, family} = Residents.name_family("The spring litter", options)

    for resident <- [hazel | young] do
      Residents.add_to_family!(%{resident_id: resident.id, family_id: family.id}, options)
    end

    for resident <- young do
      Residents.record_parent!(
        %{resident_id: resident.id, parent_id: hazel.id, role: :mother},
        options
      )
    end

    pair =
      Residents.form_group!(
        %{kind_id: kinds["Bonded pair"], resident_ids: [biscuit.id, pepper.id]},
        options
      )

    {:ok, _} = Locations.settle({:group, pair.id}, locations.pen_3.id, options)
    {:ok, _} = Locations.settle({:resident, hazel.id}, locations.pen_1.id, options)

    for resident <- young do
      {:ok, _} = Locations.settle({:resident, resident.id}, locations.pen_1.id, options)
    end

    {:ok, _} = Locations.settle({:resident, juniper.id}, locations.isolation.id, options)

    %{
      biscuit: biscuit,
      pepper: pepper,
      hazel: hazel,
      pip: hd(young),
      squeak: List.last(young),
      clover: clover,
      juniper: juniper,
      maple: maple,
      sorrel: sorrel,
      pair: pair
    }
  end

  defp journal!(%{lists: lists, options: options, residents: %{biscuit: biscuit}}) do
    now = DateTime.utc_now()

    write = fn days, facts ->
      %{resident_id: biscuit.id, happened_at: DateTime.add(now, -days * 86_400, :second)}
      |> Map.merge(facts)
      |> Journal.write_entry!(options)
    end

    write.(63, %{
      kind: :examination,
      note: "Bright and alert. Coat rough in places, nails long. No discharge from eyes or nose."
    })

    write.(63, %{
      kind: :measurement,
      measure_kind_id: lists.measure_kind.weight,
      value: 905,
      unit_id: lists.unit.g
    })

    write.(40, %{kind: :procedure, procedure_kind_id: lists.procedure_kind.desexing})

    write.(30, %{
      kind: :vaccination,
      vaccine: "Calicivirus RHDV2",
      note: "Next dose in 12 months."
    })

    write.(12, %{
      kind: :diagnosis,
      condition_id: lists.condition.respiratory_infection,
      note: "Sneezing, with a clear discharge from the nose."
    })

    prescription =
      write.(12, %{
        kind: :prescription,
        medication: "Doxycycline",
        dose: "0.3 ml two times a day",
        route: :oral,
        starts_on: DateTime.to_date(DateTime.add(now, -12 * 86_400, :second)),
        ends_on: DateTime.to_date(DateTime.add(now, -2 * 86_400, :second))
      })

    {:ok, with_facts} = Journal.entry_with_facts(prescription.id, options)

    write.(11, %{kind: :dose, prescription_id: with_facts.prescription.id, amount: "0.3 ml"})

    write.(5, %{kind: :behaviour, note: "Popcorning at floor time, and took parsley from a hand."})

    write.(1, %{
      kind: :measurement,
      measure_kind_id: lists.measure_kind.weight,
      value: 950,
      unit_id: lists.unit.g
    })
  end

  defp photos!(%{options: options, today: today, residents: residents}, picture) do
    add = fn {name, resident}, number, caption, days ->
      %{
        resident_id: resident.id,
        content: picture.(name, number),
        caption: caption,
        taken_on: Date.add(today, -days)
      }
      |> Photos.add_photo!(options)
    end

    biscuit = {"Biscuit", residents.biscuit}
    first = add.(biscuit, 1, "On the day of his arrival", 64)
    add.(biscuit, 2, "After the desexing", 39)
    add.(biscuit, 3, nil, 5)
    {:ok, _profile} = Photos.set_profile_photo(first, options)

    clover = add.({"Clover", residents.clover}, 1, "In the run", 3)
    {:ok, _profile} = Photos.set_profile_photo(clover, options)
  end

  defp expenses!(%{lists: lists, options: options, admin: admin, today: today} = context) do
    category = lists.expense_category

    expense = fn facts, options ->
      Expenses.submit_expense!(Map.merge(%{paid_by: :member}, facts), options)
    end

    vet =
      expense.(
        %{
          amount: "186.00",
          tax: "16.91",
          incurred_on: Date.add(today, -5),
          payee: "Northside Vet Clinic",
          description: "Vet consult for Biscuit",
          category_id: category.veterinary,
          resident_id: context.residents.biscuit.id
        },
        options
      )

    Expenses.attach_receipt!(
      %{expense_id: vet.id, name: "receipt.jpg", content: Rescord.StorageFixtures.photo()},
      options
    )

    Expenses.approve_expense!(vet, admin)

    expense.(
      %{
        amount: "42.50",
        incurred_on: Date.add(today, -3),
        payee: "Creekside Fuel",
        description: "Fuel for the vet run",
        category_id: category.transport
      },
      options
    )

    carrier =
      expense.(
        %{
          amount: "60.00",
          incurred_on: Date.add(today, -8),
          payee: "Pet Barn",
          description: "A new carrier",
          category_id: category.transport
        },
        options
      )

    Expenses.decline_expense!(carrier, "Use the carrier of the refuge.", admin)

    Expenses.record_expense!(
      %{
        paid_by: :organisation,
        amount: "95.00",
        tax: "8.64",
        incurred_on: Date.add(today, -10),
        payee: "Hilltop Produce",
        description: "Meadow hay, 10 bags",
        category_id: category.feed
      },
      admin
    )

    pellets =
      expense.(
        %{
          amount: "31.20",
          incurred_on: Date.add(today, -2),
          payee: "Hilltop Produce",
          description: "Guinea pig pellets",
          category_id: category.feed
        },
        admin
      )

    pellets
    |> Expenses.approve_expense!(admin)
    |> Expenses.reimburse_expense!(%{reimbursement_reference: "Bank transfer 114"}, admin)
  end

  defp tasks!(context) do
    %{organisation: organisation, lists: lists, options: options, admin: admin, today: today} =
      context

    %{biscuit: biscuit, pair: pair, juniper: juniper} = context.residents

    at = fn date, time ->
      {:ok, instant} = Accounts.local_instant(organisation, "#{Date.to_iso8601(date)}T#{time}")
      instant
    end

    plan = fn date, time, facts ->
      Tasks.plan_task!(Map.merge(%{due_at: at.(date, time)}, facts), options)
    end

    plan.(Date.add(today, -1), "16:00", %{
      title: "Trim the nails of Biscuit",
      resident_ids: [biscuit.id]
    })

    done =
      plan.(today, "00:05", %{
        title: "Check the water bottles",
        kind_id: lists.task_kind.clean,
        location_ids: [context.locations.shed.id]
      })

    {:ok, _} = Tasks.complete_task(done, %{}, options)

    plan.(today, "23:40", %{
      title: "Give Doxycycline",
      kind_id: lists.task_kind.medicate,
      resident_ids: [biscuit.id],
      assignee_ids: [context.member.id],
      note: "0.3 ml by mouth, with food."
    })

    plan.(today, "23:45", %{title: "Collect Juniper from the vet", resident_ids: [juniper.id]})
    plan.(today, "23:50", %{title: "Lock the shed"})

    Tasks.start_routine!(
      %{
        title: "Feed hay and pellets",
        kind_id: lists.task_kind.feed,
        pattern: :daily,
        times: [~T[08:00:00], ~T[17:30:00]],
        starts_on: Date.add(today, -3),
        group_ids: [pair.id],
        note: "A handful of hay each, and one spoon of pellets."
      },
      admin
    )
  end

  defp stock!(%{lists: lists, options: options, admin: admin, today: today} = context) do
    store = context.locations.shed.id

    item = fn facts -> Inventory.add_item!(facts, admin) end

    lot = fn item, facts ->
      Inventory.receive_lot!(Map.merge(%{item_id: item.id}, facts), options)
    end

    hay =
      item.(%{
        name: "Meadow hay",
        category_id: lists.item_category.food,
        unit_id: lists.unit.bag,
        reorder_level: 4
      })

    lot.(hay, %{quantity: 3, code: "H-118", location_id: store})

    pellets =
      item.(%{
        name: "Guinea pig pellets",
        category_id: lists.item_category.food,
        unit_id: lists.unit.kg,
        reorder_level: 5
      })

    lot.(pellets, %{
      quantity: 12,
      code: "P-77",
      expires_on: Date.add(today, 200),
      location_id: store
    })

    lot.(pellets, %{quantity: 2, code: "P-61", expires_on: Date.add(today, 9), location_id: store})

    doxycycline =
      item.(%{name: "Doxycycline 50 mg/ml", category_id: lists.item_category.medication})

    lot.(doxycycline, %{quantity: 1, code: "D-9", expires_on: Date.add(today, -4)})

    item.(%{name: "Fleece liners", category_id: lists.item_category.bedding})
  end
end
