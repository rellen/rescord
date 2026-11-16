defmodule RescordWeb.TimelinePagesTest do
  @moduledoc """
  Holds the page of the timeline of a resident: each event in words, with
  its time in the organisation and its person, and the words of each kind
  of event.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Journal, Locations, Residents}
  alias RescordWeb.TimelineWords

  setup context do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, member} = member!(organisation, :member, root)
    lists = lists!(organisation, root)
    options = [actor: member, tenant: organisation]
    fern = resident!(lists, options, %{name: "Fern", sex: :female})

    {:ok,
     root: root,
     organisation: organisation,
     member: member,
     options: options,
     fern: fern,
     east: Locations.add_location!(%{name: "East 1"}, actor: root, tenant: organisation),
     path: ~p"/o/#{organisation.short_name}/residents/#{fern.id}/timeline",
     conn: sign_in(context.conn, member)}
  end

  defp open(conn, path) do
    {:ok, view, _html} = live(conn, path)
    {view, render_async(view)}
  end

  test "the page does not open for a user of another organisation, or with no sign-in", context do
    other = organisation!(context.root, "Other")
    {_, outsider} = member!(other, :administrator, context.root)

    assert {:error, {:redirect, %{to: "/"}}} =
             build_conn() |> sign_in(outsider) |> live(context.path)

    assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), context.path)
  end

  test "the page goes to the residents when the resident of the address is not there", context do
    base = ~p"/o/#{context.organisation.short_name}/residents"

    for id <- [Ash.UUID.generate(), "not-an-id"] do
      assert {:error, {:live_redirect, %{to: ^base}}} =
               live(context.conn, base <> "/#{id}/timeline")
    end
  end

  test "the page says each event in words, the newest first, with its person", context do
    fern = {:resident, context.fern.id}
    Process.sleep(5)
    {:ok, _} = Locations.settle(fern, context.east.id, context.options)
    Process.sleep(5)

    group =
      Residents.form_group!(
        %{name: "The nursery", resident_ids: [context.fern.id]},
        context.options
      )

    Process.sleep(5)

    {:ok, absence} =
      Residents.start_absence(
        %{resident_id: context.fern.id, reason: "At the clinic"},
        actor: context.root,
        tenant: context.organisation
      )

    Process.sleep(5)
    :ok = Residents.finish_absence(absence, context.options)
    Process.sleep(5)

    {:ok, _} =
      Journal.write_entry(
        %{resident_id: context.fern.id, kind: :behaviour, note: "Ate well"},
        context.options
      )

    _ = group
    {view, html} = open(context.conn, context.path)

    assert html =~ "Timeline of Fern"

    words =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#timeline li p")
      |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

    assert words == [
             "Behaviour. Ate well",
             "Came back",
             "Went away: At the clinic",
             "Joined the group The nursery",
             "Placed in East 1",
             "Arrival recorded: #{RescordWeb.ResidentWords.arrival(:surrender)}, on " <>
               RescordWeb.ResidentWords.date(Date.add(Date.utc_today(), -3)),
             "Got the name Fern"
           ]

    # The member reads who made each change. An end has no person, and a
    # root user is no member.
    assert has_element?(
             view,
             "#timeline li[data-subject=placement] small",
             to_string(context.member.email)
           )

    refute has_element?(view, "#timeline li:nth-child(2) small")

    assert has_element?(
             view,
             "#timeline li:nth-child(3) small",
             "a person who is not a member now"
           )

    # The words of an event show no atom.
    refute Enum.any?(words, &(&1 =~ "_"))

    assert has_element?(view, "a", "The journal")
    assert has_element?(view, "a", "The resident")
  end

  test "the pages of the resident and of its journal link to the timeline", context do
    base = ~p"/o/#{context.organisation.short_name}/residents/#{context.fern.id}"

    {view, _html} = open(context.conn, base)
    assert has_element?(view, "a[href='#{context.path}']", "Open the timeline")

    {view, _html} = open(context.conn, base <> "/journal")
    assert has_element?(view, "a[href='#{context.path}']", "Timeline")
  end

  describe "the words of an event" do
    @names %{locations: %{"east" => "East 1"}, groups: %{"nursery" => "the group The nursery"}}

    defp words(subject, kind, record),
      do: TimelineWords.event(%{subject: subject, kind: kind, record: record}, @names)

    test "say what happened to a name, an arrival and a departure" do
      assert words(:name, :started, %{name: "Fern"}) == "Got the name Fern"
      assert words(:name, :changed, %{name: "Fernanda"}) == "The name changed to Fernanda"

      arrival = %{kind: :stray, arrived_on: ~D[2026-11-16]}
      assert words(:arrival, :started, arrival) == "Arrival recorded: Stray, on 16 November 2026"

      assert words(:arrival, :changed, arrival) ==
               "The arrival was corrected: Stray, on 16 November 2026"

      departure = %{kind: :transfer_out, departed_on: ~D[2026-11-16]}

      assert words(:departure, :started, departure) =~
               ~r/^Departure recorded: .+, on 16 November 2026$/

      assert words(:departure, :ended, departure) == "The departure was withdrawn"
    end

    test "say what happened to an absence, a placement and a group" do
      assert words(:absence, :started, %{reason: "At the clinic"}) == "Went away: At the clinic"
      assert words(:absence, :ended, %{reason: "At the clinic"}) == "Came back"

      assert words(:placement, :started, %{location_id: "east"}) == "Placed in East 1"
      assert words(:placement, :changed, %{location_id: "east"}) == "Moved to East 1"
      assert words(:placement, :ended, %{location_id: "east"}) == "Left East 1"

      assert words(:placement, :changed, %{location_id: "closed"}) ==
               "Moved to a location that is not here now"

      assert words(:group_member, :started, %{group_id: "nursery"}) ==
               "Joined the group The nursery"

      assert words(:group_member, :ended, %{group_id: "closed"}) ==
               "Left a group that is not here now"

      member = fn name -> %{resident: %{name: name}} end

      assert TimelineWords.group(%{name: "The nursery", members: []}) == "the group The nursery"

      assert TimelineWords.group(%{name: nil, members: [member.("Sage"), member.("Fern")]}) ==
               "the group of Fern and Sage"

      assert TimelineWords.group(%{name: nil, members: [member.(nil)]}) ==
               "the group of a resident with no name"

      assert TimelineWords.group(%{name: nil, members: []}) == "a group that has no members now"
    end

    test "are there for each subject of the timeline" do
      assert Enum.sort(TimelineWords.subjects()) ==
               Enum.sort([
                 :entry,
                 :name,
                 :arrival,
                 :departure,
                 :absence,
                 :placement,
                 :group_member
               ])
    end
  end
end
