defmodule RescordWeb.TimelinePagesTest do
  @moduledoc """
  Holds the page of the timeline of a resident: each event in words, with
  its time in the organisation and its person, and the words of each kind
  of event. The page tests find what a person finds (ADR 0107).

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

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

  defp events, do: main() |> list("The events")

  test "the page does not open for a user of another organisation, or with no sign-in", context do
    other = organisation!(context.root, "Other")
    {_, outsider} = member!(other, :administrator, context.root)

    build_conn() |> sign_in(outsider) |> visit(context.path) |> assert_path("/")
    build_conn() |> visit(context.path) |> assert_path("/")
  end

  test "the page goes to the residents when the resident of the address is not there", context do
    base = ~p"/o/#{context.organisation.short_name}/residents"

    for id <- [Ash.UUID.generate(), "not-an-id"] do
      context.conn |> visit(base <> "/#{id}/timeline") |> assert_path(base)
    end
  end

  test "the page says each event in words, the newest first, with its person", context do
    fern = {:resident, context.fern.id}
    Process.sleep(5)
    {:ok, _} = Locations.settle(fern, context.east.id, context.options)
    Process.sleep(5)

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

    session =
      context.conn
      |> visit(context.path)
      |> assert_has(main() |> heading(level: 1), text: "Timeline of Fern")

    # Each event has its time, its words and its person, the newest first.
    words = [
      "Behaviour. Ate well",
      "Came back",
      "Went away: At the clinic",
      "Joined the group The nursery",
      "Placed in East 1",
      "Arrival recorded: #{RescordWeb.ResidentWords.arrival(:surrender)}, on " <>
        RescordWeb.ResidentWords.date(Date.add(Date.utc_today(), -3)),
      "Got the name Fern"
    ]

    shown = names(session, events() |> item(nil))
    assert length(shown) == length(words)
    for {event, said} <- Enum.zip(shown, words), do: assert(event =~ said)

    # The member reads who made each change. An end has no person, and a
    # root user who is not a member is the operator (ADR 0105).
    member = to_string(context.member.email)
    assert text(session, events() |> item(~r/Placed in East 1/)) =~ ~r/East 1 #{member}$/
    assert text(session, events() |> item(~r/Came back/)) =~ ~r/Came back$/

    assert text(session, events() |> item(~r/Went away/)) =~
             ~r/At the clinic Rescord operator$/

    # The words of an event show no atom.
    refute Enum.any?(shown, &(&1 =~ "_"))

    session
    |> assert_has(main() |> link("The journal"))
    |> assert_has(navigation("Breadcrumb") |> link("Fern"))
  end

  test "the pages of the resident and of its journal link to the timeline", context do
    base = ~p"/o/#{context.organisation.short_name}/residents/#{context.fern.id}"

    assert context.conn |> visit(base) |> href(main() |> link("Open the timeline")) ==
             context.path

    assert context.conn |> visit(base <> "/journal") |> href(main() |> link("Timeline")) ==
             context.path
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

    test "say when a condition was resolved, and when it was opened again" do
      event = %{
        subject: :episode,
        kind: :resolved,
        condition: "Bumblefoot",
        record: %{ended_on: ~D[2026-11-16]}
      }

      assert TimelineWords.event(event, @names) ==
               "Bumblefoot was resolved. Its last day was 16 November 2026"

      assert TimelineWords.event(%{event | kind: :reopened}, @names) ==
               "Bumblefoot was opened again: it was not over"
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
                 :group_member,
                 :episode
               ])
    end
  end
end
