defmodule Rescord.TimelineTest do
  @moduledoc """
  Holds the timeline of a resident (`docs/domain.md`, section 5.6, and
  ADR 0035): its journal entries together with the changes that Rescord
  recorded, the newest first, for a person who can read the resident.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Journal, Locations, Residents}

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    admin = [actor: administrator, tenant: organisation]
    options = [actor: member, tenant: organisation]

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     admin: admin,
     options: options,
     east: Locations.add_location!(%{name: "East 1"}, admin),
     west: Locations.add_location!(%{name: "West 1"}, admin),
     fern: resident!(lists, options, %{name: "Fern", sex: :female})}
  end

  # The events of the timeline, the oldest first, each as its subject and
  # its kind.
  defp events(context, options \\ nil) do
    {:ok, timeline} = Journal.timeline(context.fern.id, options || context.options)
    timeline |> Enum.reverse() |> Enum.map(&{&1.subject, &1.kind})
  end

  # Each write is at an instant of its own.
  defp pause, do: Process.sleep(5)

  test "a new resident has its name and its arrival, in that order", context do
    assert events(context) == [name: :started, arrival: :started]

    {:ok, [arrival, name]} = Journal.timeline(context.fern.id, context.options)
    assert name.record.name == "Fern"
    assert name.user_id == context.member.id
    assert arrival.record.kind == :surrender
  end

  test "has each change that Rescord recorded, with who made it", context do
    fern = {:resident, context.fern.id}
    pause()
    {:ok, _} = Locations.settle(fern, context.east.id, context.options)
    pause()
    {:ok, placement} = Locations.settle(fern, context.west.id, context.admin)
    pause()

    {:ok, absence} =
      Residents.start_absence(
        %{resident_id: context.fern.id, reason: "At the clinic"},
        context.options
      )

    pause()
    :ok = Residents.finish_absence(absence, context.options)
    pause()
    group = Residents.form_group!(%{resident_ids: [context.fern.id]}, context.options)
    pause()
    {:ok, %{members: [tie]}} = Residents.group_with_facts(group.id, context.options)
    :ok = Residents.leave_group(tie, context.options)
    pause()
    :ok = Locations.finish_placement(placement, context.options)
    pause()

    {:ok, departure} =
      Residents.record_departure(
        %{resident_id: context.fern.id, kind: :transfer_out, departed_on: Date.utc_today()},
        context.options
      )

    pause()
    :ok = Residents.withdraw_departure(departure, context.options)

    assert events(context) == [
             name: :started,
             arrival: :started,
             placement: :started,
             placement: :changed,
             absence: :started,
             absence: :ended,
             group_member: :started,
             group_member: :ended,
             placement: :ended,
             departure: :started,
             departure: :ended
           ]

    {:ok, timeline} = Journal.timeline(context.fern.id, context.options)
    by = fn subject, kind -> Enum.find(timeline, &(&1.subject == subject and &1.kind == kind)) end

    # A move names its location and the member who made it.
    assert by.(:placement, :started).record.location_id == context.east.id
    assert by.(:placement, :started).user_id == context.member.id
    assert by.(:placement, :changed).record.location_id == context.west.id
    assert by.(:placement, :changed).user_id == context.administrator.id
    assert by.(:placement, :ended).record.location_id == context.west.id

    assert by.(:absence, :started).record.reason == "At the clinic"
    assert by.(:group_member, :started).record.group_id == group.id
    # The versions do not say who ended a record.
    assert by.(:absence, :ended).user_id == nil
  end

  test "has the journal entries at the time that each thing happened", context do
    pause()
    {:ok, _} = Locations.settle({:resident, context.fern.id}, context.east.id, context.options)
    pause()

    {:ok, _} =
      Journal.write_entry(
        %{resident_id: context.fern.id, kind: :behaviour, note: "Ate well"},
        context.options
      )

    # An entry about a thing that happened an hour ago is before each change
    # that Rescord recorded now.
    {:ok, _} =
      Journal.write_entry(
        %{
          resident_id: context.fern.id,
          kind: :general,
          note: "Arrived in a carrier",
          happened_at: DateTime.add(DateTime.utc_now(), -1, :hour)
        },
        context.options
      )

    assert events(context) == [
             entry: :written,
             name: :started,
             arrival: :started,
             placement: :started,
             entry: :written
           ]

    {:ok, [newest | _] = timeline} = Journal.timeline(context.fern.id, context.options)
    assert newest.record.note == "Ate well"
    assert newest.user_id == context.member.id
    assert List.last(timeline).record.note == "Arrived in a carrier"
  end

  test "has a new name as a change", context do
    pause()
    {:ok, _} = Residents.revise_resident(context.fern, %{name: "Fernanda"}, context.options)

    {:ok, [renamed | _]} = Journal.timeline(context.fern.id, context.options)
    assert {renamed.subject, renamed.kind, renamed.record.name} == {:name, :changed, "Fernanda"}
  end

  test "does not have the changes of another resident", context do
    other =
      Residents.register_resident!(
        %{
          name: "Sage",
          species_id: context.fern.species_id,
          sex: :female,
          arrival_kind: :stray,
          arrived_on: Date.utc_today()
        },
        context.options
      )

    {:ok, _} = Locations.settle({:resident, other.id}, context.east.id, context.options)

    assert events(context) == [name: :started, arrival: :started]
  end

  test "is empty for a user of another organisation, and for nobody", context do
    other = organisation!(context.root, "Other")
    {_, outsider} = member!(other, :administrator, context.root)

    # The resident has a change of each domain to read.
    {:ok, _} = Locations.settle({:resident, context.fern.id}, context.east.id, context.options)
    assert [%{subject: :placement}] = Locations.changes(context.fern.id, context.options)
    assert [_name, _arrival] = Residents.changes(context.fern.id, context.options)

    for actor <- [outsider, nil] do
      options = [actor: actor, tenant: context.organisation]

      assert {:ok, []} = Journal.timeline(context.fern.id, options)
      assert Residents.changes(context.fern.id, options) == []
      assert Locations.changes(context.fern.id, options) == []
    end

    # A root user reads it.
    assert events(context, actor: context.root, tenant: context.organisation) ==
             [name: :started, arrival: :started, placement: :started]
  end
end
