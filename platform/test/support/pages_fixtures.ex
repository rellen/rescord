defmodule RescordWeb.PagesFixtures do
  @moduledoc """
  A refuge with a record of each kind, and the address of each kind of page
  of an organisation. The browser tests that visit each page read it:
  `RescordWeb.Features.PhoneTest` (ADR 0061) and
  `RescordWeb.Features.AccessibilityTest` (ADR 0090). Add a new page to
  `pages` here, with the records that it shows, and both tests hold it.

  The administrator has a long address and the organisation a long name,
  because those are what broke the menu.

  The store of the files must be there first: the receipts of an expense
  are files of the store.
  """

  # Test support may use any boundary, and any test may use it (ADR 0009).
  use Boundary, top_level?: true, check: [in: false, out: false]

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.StorageFixtures

  alias Rescord.{Accounts, Expenses, Inventory, Journal, Locations, Residents, Tasks}

  @doc """
  Makes the refuge in the directory `tmp_dir`, with an administrator who
  has the address `address`. Returns `home`, the path of the organisation,
  `root`, `organisation`, and `pages`, the paths of the pages.
  """
  def refuge!(tmp_dir, address) do
    disk_store!(tmp_dir)
    root = root!()
    organisation = organisation!(root, "Wattle Creek Small Animal Refuge")
    {_member, user} = member!(organisation, :administrator, root, address)

    # The organisation names its tax, so the pages of the expenses have the
    # field of the tax and the form that corrects it (ADR 0089).
    organisation = Accounts.set_organisation_tax_name!(organisation, "GST", actor: user)

    lists = lists!(organisation, root)
    options = [actor: root, tenant: organisation]

    resident = resident!(lists, options, %{name: "Sir Reginald Fluffington the Third"})
    clover = resident!(lists, options, %{name: "Clover", sex: :female})

    # The charts of the measurements (ADR 0080): a weight with a large
    # number, a companion that is weighed in another unit, and a group.
    for {resident, values, unit} <- [
          {resident, ~w(690 672 760 870 915 1095), lists.unit.g},
          {clover, ~w(0.61 0.64 0.7 0.82 0.9 0.985), lists.unit.kg}
        ],
        {value, days} <- Enum.zip(values, [30, 23, 19, 14, 7, 1]) do
      Journal.write_entry!(
        %{
          resident_id: resident.id,
          kind: :measurement,
          measure_kind_id: lists.measure_kind.weight,
          value: value,
          unit_id: unit,
          note: "Before breakfast",
          happened_at: DateTime.add(DateTime.utc_now(), -days, :day)
        },
        options
      )
    end

    group =
      Residents.form_group!(
        %{name: "The companions of the long hutch", resident_ids: [resident.id, clover.id]},
        options
      )

    # A condition of the resident, with a long note, for the pages of the
    # conditions (ADR 0083).
    Journal.write_entry!(
      %{
        resident_id: resident.id,
        kind: :diagnosis,
        condition_id: lists.condition.respiratory_infection,
        chronic: true
      },
      options
    )

    {:ok, [episode]} = Journal.episodes_of(resident.id, options)

    {:ok, _episode} =
      Journal.revise_episode(
        episode,
        %{note: "Sneezes at night, and more in the cold months of the year"},
        options
      )

    shed = Locations.add_location!(%{name: "Feed shed"}, options)
    hay = Inventory.add_item!(%{name: "Meadow hay", unit_id: lists.unit.bag}, options)

    Inventory.receive_lot!(
      %{item_id: hay.id, code: "B-1", quantity: 10, location_id: shed.id},
      options
    )

    {:ok, due_at} =
      Accounts.local_instant(
        organisation,
        "#{Date.to_iso8601(Accounts.today(organisation))}T23:30"
      )

    Tasks.plan_task!(
      %{
        title: "Give Sir Reginald his evening medication",
        due_at: due_at,
        kind_id: lists.task_kind.medicate,
        resident_ids: [resident.id],
        assignee_ids: [user.id],
        note: "With food"
      },
      options
    )

    # An expense that waits, with a photo and a PDF, and one to pay back.
    expense =
      Expenses.submit_expense!(
        %{
          paid_by: :member,
          amount: "1186.00",
          tax: "107.82",
          incurred_on: Accounts.today(organisation),
          payee: "Northside Veterinary Clinic and Animal Hospital",
          description: "Consult after hours for Sir Reginald Fluffington the Third",
          category_id: lists.expense_category.veterinary,
          resident_id: resident.id,
          note: "The fee for after hours is in the amount."
        },
        actor: user,
        tenant: organisation
      )

    for {name, content} <- [
          {"a-receipt-with-a-long-name-from-the-clinic.jpg", jpeg()},
          {"invoice.pdf", pdf()}
        ] do
      Expenses.attach_receipt!(%{expense_id: expense.id, name: name, content: content},
        actor: user,
        tenant: organisation
      )
    end

    owed =
      Expenses.submit_expense!(
        %{
          paid_by: :member,
          amount: "58.25",
          tax: "5.30",
          incurred_on: Accounts.today(organisation),
          payee: "Creekside Fuel",
          description: "Fuel",
          category_id: lists.expense_category.transport
        },
        actor: user,
        tenant: organisation
      )

    Expenses.approve_expense!(owed, options)

    home = "/o/#{organisation.short_name}"

    %{
      home: home,
      root: root,
      organisation: organisation,
      pages:
        ["/", "/colophon", home] ++
          Enum.map(
            ~w(tasks routines residents residents/new residents/#{resident.id}
              residents/#{resident.id}/edit residents/#{resident.id}/journal
              residents/conditions residents/#{resident.id}/journal?episode=#{episode.id}
              residents/#{resident.id}/photos residents/#{resident.id}/timeline
              residents/#{resident.id}/measurements groups groups/#{group.id}/measurements housing
              housing/#{shed.id} inventory inventory/#{hay.id} inventory/suppliers tools tools/dose
              reports lists members roles partners transfers settings settings/ruby export
              calendar expenses expenses/new expenses/#{expense.id} expenses/#{expense.id}/edit
              expenses/#{owed.id}),
            &"#{home}/#{&1}"
          )
    }
  end
end
