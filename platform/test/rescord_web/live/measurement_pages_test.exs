defmodule RescordWeb.MeasurementPagesTest do
  @moduledoc """
  Holds the pages of the measurements over time (ADR 0080): the page of a
  resident with a card, a chart and a table for each kind, the page of a
  group, and the newest values on the page of a resident.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import RescordWeb.Roles, only: [has?: 2, main: 0, alert: 1]
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Journal, Residents}

  setup context do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    options = [actor: member, tenant: organisation]
    biscuit = resident!(lists, options)

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     lists: lists,
     options: options,
     biscuit: biscuit,
     base: ~p"/o/#{organisation.short_name}",
     path: ~p"/o/#{organisation.short_name}/residents/#{biscuit.id}/measurements",
     conn: sign_in(context.conn, member)}
  end

  defp open(conn, path) do
    {:ok, view, _html} = live(conn, path)
    {view, render_async(view)}
  end

  # The page after a measurement of a kind: the form is open again with
  # that kind (ADR 0111).
  defp again(context, kind),
    do: context.path <> "?again=#{Map.fetch!(context.lists.measure_kind, kind)}"

  # Records a measurement of a resident some days ago, at 08:30 of the
  # organisation on that day.
  defp measure!(context, resident, kind, value, unit, days_ago, extra \\ %{}) do
    day = Date.add(Accounts.today(context.organisation), -days_ago)
    at = Accounts.local_instant(context.organisation, day, ~T[08:30:00])

    %{
      resident_id: resident.id,
      kind: :measurement,
      measure_kind_id: Map.fetch!(context.lists.measure_kind, kind),
      value: value,
      unit_id: unit && Map.fetch!(context.lists.unit, unit),
      happened_at: at
    }
    |> Map.merge(extra)
    |> Journal.write_entry!(context.options)
  end

  defp date(context, days_ago) do
    RescordWeb.ResidentWords.date(Date.add(Accounts.today(context.organisation), -days_ago))
  end

  defp weights!(context) do
    for {value, days_ago} <- [{"690", 23}, {"672", 19}, {"760", 14}, {"870", 7}, {"915", 0}] do
      # The newest one is of this instant, and not of 08:30, which can be after now.
      extra = if days_ago == 0, do: %{happened_at: nil}, else: %{}
      measure!(context, context.biscuit, :weight, value, :g, days_ago, extra)
    end
  end

  test "the pages do not open for a user of another organisation, or with no sign-in", context do
    other = organisation!(context.root, "Other")
    {_, outsider} = member!(other, :administrator, context.root)
    group = Residents.form_group!(%{resident_ids: [context.biscuit.id]}, context.options)
    group_path = "#{context.base}/groups/#{group.id}/measurements"

    for path <- [context.path, group_path] do
      assert {:error, {:redirect, %{to: "/"}}} = build_conn() |> sign_in(outsider) |> live(path)
      assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), path)
    end

    missing = "#{context.base}/residents/#{Ash.UUID.generate()}/measurements"
    assert {:error, {:redirect, %{to: to}}} = live(context.conn, missing)
    assert to == "#{context.base}/residents"

    missing = "#{context.base}/groups/#{Ash.UUID.generate()}/measurements"
    assert {:error, {:redirect, %{to: to}}} = live(context.conn, missing)
    assert to == "#{context.base}/groups"
  end

  describe "the measurements of a resident" do
    test "with none, the page says so and offers the form", context do
      {view, html} = open(context.conn, context.path)

      assert html =~ "Measurements of Biscuit"
      assert html =~ "No measurement yet. Record the first one with the form above."
      assert has_element?(view, "#record #measurement")
      refute has_element?(view, "nav[data-choice]")
      refute has_element?(view, "article[data-measure]")
    end

    test "has a card for each kind, with the newest value and its change", context do
      weights!(context)
      measure!(context, context.biscuit, :temperature, "38.5", nil, 2)
      kinds = context.lists.measure_kind

      {view, _html} = open(context.conn, context.path)

      assert has_element?(view, "#measure-#{kinds.weight} h2", "Weight")
      assert has_element?(view, "#measure-#{kinds.weight} p[data-figure] strong", "915 g")

      assert has_element?(
               view,
               "#measure-#{kinds.weight} p[data-change=up]",
               "45 g more than on #{date(context, 7)}"
             )

      # One measurement is no chart, and has no change.
      assert has_element?(view, "#measure-#{kinds.temperature} p[data-figure] strong", "38.5")
      refute has_element?(view, "#measure-#{kinds.temperature} [data-change]")
      refute has_element?(view, "#measure-#{kinds.temperature} figure")

      assert has_element?(
               view,
               "#measure-#{kinds.temperature}",
               "A chart starts with the second one"
             )

      # The cards are in the order of the names of the kinds.
      assert view
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("article[data-measure] h2")
             |> Enum.map(&LazyHTML.text/1) == ["Temperature", "Weight"]
    end

    test "has a chart that is an image with a name and words that say what it shows", context do
      weights!(context)
      kind = context.lists.measure_kind.weight

      {view, _html} = open(context.conn, context.path)

      assert has_element?(
               view,
               "#chart-#{kind} svg[role=img][aria-label='Weight of Biscuit, in g'][aria-describedby='chart-#{kind}-summary']"
             )

      assert has_element?(
               view,
               "figcaption#chart-#{kind}-summary",
               "5 measurements from #{date(context, 23)} to #{date(context, 0)}. " <>
                 "The lowest is 672 g, on #{date(context, 19)}. " <>
                 "The highest is 915 g, on #{date(context, 0)}. The newest is 915 g."
             )

      assert view
             |> element("#chart-#{kind} [data-dots]")
             |> render()
             |> String.split("<circle")
             |> length() == 6

      assert has_element?(view, "#chart-#{kind} p[data-span] span", date(context, 23))
    end

    test "has each value of a chart in a table, with its change and a link to its entry",
         context do
      [first | _rest] = weights!(context)
      kind = context.lists.measure_kind.weight

      measure!(context, context.biscuit, :weight, "740", :g, 16, %{note: "After a meal"})

      {view, _html} = open(context.conn, context.path)

      assert has_element?(view, "details#table-#{kind} summary", "The 6 measurements as a table")
      assert has_element?(view, "#table-#{kind} th[scope=col]", "Value")

      row = "#table-#{kind} tr#point-#{first.id}"
      assert has_element?(view, "#{row} th[scope=row] a", date(context, 23))

      assert has_element?(
               view,
               "#{row} a[href='#{context.base}/residents/#{context.biscuit.id}/journal?entry=#{first.id}']"
             )

      assert has_element?(view, "#{row} td[data-label=Value]", "690 g")
      # The first measurement has no change: the cell is empty, so the card
      # of a phone leaves it out.
      refute has_element?(view, "#{row} [data-change]")
      assert has_element?(view, "#{row} td[data-label=Change]:empty")

      assert has_element?(
               view,
               "#table-#{kind} td[data-label=Change] [data-change=down]",
               "18 g less"
             )

      assert has_element?(
               view,
               "#table-#{kind} td[data-label=Change] [data-change=up]",
               "68 g more"
             )

      assert has_element?(view, "#table-#{kind} td[data-label=Note]", "After a meal")

      # The newest row is the first.
      rows =
        view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query("#table-#{kind} tbody tr")

      assert rows |> Enum.at(0) |> LazyHTML.text() =~ "915 g"
    end

    test "shows a measurement in another unit in the unit of the newest one", context do
      measure!(context, context.biscuit, :weight, "0.61", :kg, 5)
      measure!(context, context.biscuit, :weight, "690", :g, 1)
      kind = context.lists.measure_kind.weight

      {view, _html} = open(context.conn, context.path)

      assert has_element?(view, "#measure-#{kind} p[data-change=up]", "80 g more than on")
      assert has_element?(view, "#table-#{kind} td[data-label=Value]", "610 g")

      assert has_element?(
               view,
               "#table-#{kind} td[data-label=Value] small",
               "recorded as 0.61 kg"
             )
    end

    test "says which measurements are not in the chart, and has them in the table", context do
      measure!(context, context.biscuit, :weight, "2", :bag, 6)
      measure!(context, context.biscuit, :weight, "85", :g, 5)
      measure!(context, context.biscuit, :weight, "110", :g, 1)
      kind = context.lists.measure_kind.weight

      {view, _html} = open(context.conn, context.path)

      assert has_element?(view, "#measure-#{kind}", "One measurement is not in the chart")
      assert has_element?(view, "#table-#{kind} summary", "The 3 measurements as a table")
      assert has_element?(view, "#table-#{kind} td[data-label=Value]", "2 bag")
      assert has_element?(view, "#table-#{kind} td[data-label=Change]", "Not in the chart")
      # The chart has the two points in grams.
      assert has_element?(view, "figcaption", "2 measurements from")
    end

    test "writes two measurements of one day with their times", context do
      day = Date.add(Accounts.today(context.organisation), -1)

      for {time, value} <- [{~T[08:05:00], "39.4"}, {~T[17:40:00], "39.7"}] do
        measure!(context, context.biscuit, :temperature, value, nil, 1, %{
          happened_at: Accounts.local_instant(context.organisation, day, time)
        })
      end

      {view, _html} = open(context.conn, context.path)

      assert has_element?(
               view,
               "p[data-figure] span",
               "#{date(context, 1)}, #{RescordWeb.Locale.time(~T[17:40:00])}"
             )

      assert has_element?(
               view,
               "p[data-change=up]",
               "0.3 more than on #{date(context, 1)}, #{RescordWeb.Locale.time(~T[08:05:00])}"
             )
    end
  end

  describe "the time range" do
    setup context do
      weights!(context)
      measure!(context, context.biscuit, :weight, "400", :g, 200)
      measure!(context, context.biscuit, :temperature, "38.5", nil, 120)
      :ok
    end

    test "is each measurement at first, and the address holds another choice", context do
      {view, _html} = open(context.conn, context.path)

      assert has_element?(view, "nav[data-choice] a[aria-current=true]", "All")
      assert has_element?(view, "figcaption", "6 measurements from #{date(context, 200)}")

      html = view |> element("nav[data-choice] a", "30 days") |> render_click()
      assert_patch(view, context.path <> "?range=30")
      assert html =~ "5 measurements from #{date(context, 23)}"
      assert has_element?(view, "nav[data-choice] a[aria-current=true]", "30 days")
      refute has_element?(view, "nav[data-choice] a[aria-current=true]", "All")
    end

    test "keeps the newest value of a kind with no measurement in the range", context do
      kind = context.lists.measure_kind.temperature
      {view, _html} = open(context.conn, context.path <> "?range=90")

      assert has_element?(view, "#measure-#{kind} p[data-figure] strong", "38.5")
      assert has_element?(view, "#measure-#{kind}", "No measurement in this time.")
      refute has_element?(view, "#measure-#{kind} figure")
      refute has_element?(view, "#measure-#{kind} details")
    end

    test "keeps the change of the first point of the range from the point before it", context do
      kind = context.lists.measure_kind.weight
      {view, _html} = open(context.conn, context.path <> "?range=30")

      # 690 g is the first of the range, and 400 g came before it.
      assert has_element?(view, "#table-#{kind} [data-change=up]", "290 g more")
    end

    test "is each measurement for a range that the page does not know", context do
      {view, _html} = open(context.conn, context.path <> "?range=7000")

      assert has_element?(view, "nav[data-choice] a[aria-current=true]", "All")
      assert has_element?(view, "figcaption", "6 measurements")
    end
  end

  describe "a point of a chart" do
    test "that a person presses is written in words, and a second press lets it go", context do
      [_first, second | _rest] = weights!(context)
      kind = context.lists.measure_kind.weight

      {view, _html} = open(context.conn, context.path)
      refute has_element?(view, "p[data-picked]")

      point = "#chart-#{kind} [data-points] g[phx-value-point='#{second.id}']"
      view |> element(point) |> render_click()

      assert has_element?(view, "#measure-#{kind} p[data-picked][role=status] strong", "672 g")
      assert has_element?(view, "p[data-picked]", "on #{date(context, 19)}")
      assert has_element?(view, "p[data-picked]", "18 g less than on #{date(context, 23)}")

      assert has_element?(
               view,
               "p[data-picked] a[href='#{context.base}/residents/#{context.biscuit.id}/journal?entry=#{second.id}']",
               "Open the entry"
             )

      # The chart and the table mark the point.
      assert has_element?(view, "#{point}[data-selected]")
      assert has_element?(view, "tr#point-#{second.id}[aria-current=true]")

      view |> element(point) |> render_click()
      refute has_element?(view, "p[data-picked]")
      refute has_element?(view, "[data-selected]")
    end

    test "that is not on the page changes nothing", context do
      weights!(context)
      {view, _html} = open(context.conn, context.path)

      for params <- [
            %{"point" => Ash.UUID.generate()},
            %{"point" => %{"a" => "map"}},
            %{"other" => "field"},
            %{}
          ] do
        render_click(view, "pick", params)
        refute has_element?(view, "p[data-picked]")
      end
    end

    test "is let go when the time range changes", context do
      [first | _rest] = weights!(context)
      {view, _html} = open(context.conn, context.path)

      render_click(view, "pick", %{"point" => first.id})
      assert has_element?(view, "p[data-picked]")

      view |> element("nav[data-choice] a", "90 days") |> render_click()
      refute has_element?(view, "p[data-picked]")
    end
  end

  describe "the form that records a measurement" do
    test "is open again after a measurement, with its kind, and the value takes the focus",
         context do
      weight = context.lists.measure_kind.weight
      {view, _html} = open(context.conn, context.path)

      refute has_element?(view, "details#record[open]")
      refute has_element?(view, "#measurement input[autofocus]")

      {view, _html} = open(context.conn, again(context, :weight))

      assert has_element?(view, "details#record[open]")
      assert has_element?(view, "#measurement option[selected][value='#{weight}']", "Weight")
      assert has_element?(view, "#measurement input[name='measurement[value]'][autofocus]")
    end

    test "is closed for a kind that is not of the page", context do
      {view, _html} = open(context.conn, context.path <> "?again=no-such-kind")

      refute has_element?(view, "details#record[open]")
    end

    test "writes a journal entry, and the page shows the new value", context do
      lists = context.lists
      {view, _html} = open(context.conn, context.path)

      {:ok, view, _html} =
        view
        |> form("#measurement",
          measurement: %{
            measure_kind_id: lists.measure_kind.weight,
            value: "1095",
            unit_id: lists.unit.g,
            note: "Before breakfast"
          }
        )
        |> render_submit()
        |> follow_redirect(context.conn, again(context, :weight))

      assert render(view) =~ "The measurement is recorded."
      assert has_element?(view, "p[data-figure] strong", "1,095 g")

      {:ok, [entry]} = Journal.entries(context.biscuit.id, context.options)
      assert entry.kind == :measurement
      assert entry.note == "Before breakfast"
      assert entry.author_id == context.member.id
      assert Decimal.equal?(entry.measurement.value, 1095)
      assert entry.measurement.unit_id == lists.unit.g
    end

    test "records at the time that the member gives, in the zone of the organisation", context do
      lists = context.lists
      day = Date.add(Accounts.today(context.organisation), -3)
      {view, _html} = open(context.conn, context.path <> "?range=30")

      {:ok, view, _html} =
        view
        |> form("#measurement",
          measurement: %{
            measure_kind_id: lists.measure_kind.temperature,
            value: "38.5",
            at: "#{Date.to_iso8601(day)}T07:15"
          }
        )
        |> render_submit()
        # The page keeps its time range.
        |> follow_redirect(
          context.conn,
          context.path <> "?again=#{lists.measure_kind.temperature}&range=30"
        )

      assert has_element?(view, "p[data-figure] span", date(context, 3))

      {:ok, [entry]} = Journal.entries(context.biscuit.id, context.options)

      assert DateTime.compare(
               entry.happened_at,
               Accounts.local_instant(context.organisation, day, ~T[07:15:00])
             ) == :eq
    end

    test "offers the units of the kind, with the unit of the newest measurement chosen",
         context do
      lists = context.lists

      Rescord.Lists.set_units(lists.measure_kind.weight, [lists.unit.g, lists.unit.kg],
        actor: context.administrator,
        tenant: context.organisation
      )

      measure!(context, context.biscuit, :weight, "0.61", :kg, 2)

      {view, _html} = open(context.conn, context.path)

      # No kind yet: each unit of the organisation.
      assert has_element?(view, "#measurement select[name='measurement[unit_id]'] option", "bag")

      view
      |> form("#measurement", measurement: %{measure_kind_id: lists.measure_kind.weight})
      |> render_change()

      refute has_element?(view, "#measurement select[name='measurement[unit_id]'] option", "bag")

      assert has_element?(
               view,
               "#measurement select[name='measurement[unit_id]'] option[selected][value='#{lists.unit.kg}']"
             )

      # The person chooses another unit, and the form keeps it while they type.
      view
      |> form("#measurement",
        measurement: %{
          measure_kind_id: lists.measure_kind.weight,
          unit_id: lists.unit.g,
          value: "7"
        }
      )
      |> render_change()

      assert has_element?(
               view,
               "#measurement select[name='measurement[unit_id]'] option[selected][value='#{lists.unit.g}']"
             )
    end

    test "says what the journal refused, and keeps what the person typed", context do
      lists = context.lists

      Rescord.Lists.set_units(lists.measure_kind.weight, [lists.unit.g],
        actor: context.administrator,
        tenant: context.organisation
      )

      {view, _html} = open(context.conn, context.path)

      # A unit that the kind does not accept: the browser offers only grams,
      # so this is a request that a person wrote by hand.
      render_submit(view, "record", %{
        "measurement" => %{
          "measure_kind_id" => lists.measure_kind.weight,
          "value" => "12",
          "unit_id" => lists.unit.bag
        }
      })

      assert has?(view, main() |> alert())
      assert has_element?(view, "#measurement input[name='measurement[value]'][value='12']")
      assert {:ok, []} = Journal.entries(context.biscuit.id, context.options)

      # A time after now.
      html =
        render_submit(view, "record", %{
          "measurement" => %{
            "measure_kind_id" => lists.measure_kind.weight,
            "value" => "12",
            "at" => "2999-01-01T08:00"
          }
        })

      assert html =~ "The time cannot be after now"

      # A request with a shape that the page does not know changes nothing.
      for params <- [
            %{"measurement" => "text"},
            %{"measurement" => %{"value" => %{"a" => 1}}},
            %{}
          ] do
        render_submit(view, "record", params)
      end

      assert {:ok, []} = Journal.entries(context.biscuit.id, context.options)
    end

    test "is not there for a role that cannot write to the journal", context do
      weights!(context)

      {:ok, reader_role} =
        Accounts.define_role(%{name: "Reader", powers: []},
          actor: context.administrator,
          tenant: context.organisation
        )

      {reader_member, reader} = member!(context.organisation, :member, context.administrator)

      {:ok, _member} =
        Accounts.set_member_role(reader_member, reader_role.id,
          actor: context.administrator,
          tenant: context.organisation
        )

      {view, _html} = open(sign_in(build_conn(), reader), context.path)

      assert has_element?(view, "p[data-figure] strong", "915 g")
      refute has_element?(view, "#record")

      # The action refuses a request that the reader writes by hand.
      render_submit(view, "record", %{
        "measurement" => %{
          "measure_kind_id" => context.lists.measure_kind.weight,
          "value" => "1"
        }
      })

      {:ok, entries} = Journal.entries(context.biscuit.id, context.options)
      assert length(entries) == 5
    end
  end

  describe "a kind with a standard unit (ADR 0094)" do
    defp standard!(context, unit) do
      {:ok, _} =
        Rescord.Lists.set_standard_unit(
          context.lists.measure_kind.weight,
          unit && Map.fetch!(context.lists.unit, unit),
          actor: context.administrator,
          tenant: context.organisation
        )
    end

    test "has its card, its chart and its table in that unit, whatever was recorded last",
         context do
      measure!(context, context.biscuit, :weight, "690", :g, 5)
      measure!(context, context.biscuit, :weight, "0.76", :kg, 1)
      standard!(context, :g)
      kind = context.lists.measure_kind.weight

      {view, _html} = open(context.conn, context.path)

      assert has_element?(view, "#measure-#{kind} p[data-figure] strong", "760 g")
      assert has_element?(view, "#measure-#{kind} p[data-change=up]", "70 g more than on")

      assert has_element?(
               view,
               "#chart-#{kind} svg[role=img][aria-label='Weight of Biscuit, in g']"
             )

      assert has_element?(view, "#table-#{kind} td[data-label=Value]", "760 g")

      assert has_element?(
               view,
               "#table-#{kind} td[data-label=Value] small",
               "recorded as 0.76 kg"
             )

      # Another standard unit changes the page, and no record.
      standard!(context, :kg)
      {view, _html} = open(context.conn, context.path)

      assert has_element?(view, "#measure-#{kind} p[data-figure] strong", "0.76 kg")

      assert has_element?(
               view,
               "#chart-#{kind} svg[role=img][aria-label='Weight of Biscuit, in kg']"
             )

      assert has_element?(view, "#table-#{kind} td[data-label=Value] small", "recorded as 690 g")
    end

    test "has the standard unit chosen in the form, and no choice of no unit", context do
      lists = context.lists
      unit = "#measurement select[name='measurement[unit_id]']"

      # The newest measurement is in kg: the form chooses the standard unit.
      measure!(context, context.biscuit, :weight, "0.61", :kg, 2)
      standard!(context, :g)

      {view, _html} = open(context.conn, context.path)
      assert has_element?(view, "#{unit} option", "No unit")

      view
      |> form("#measurement", measurement: %{measure_kind_id: lists.measure_kind.weight})
      |> render_change()

      assert has_element?(view, "#{unit}[required] option[selected][value='#{lists.unit.g}']")
      assert has_element?(view, "#{unit} option", "kg")
      refute has_element?(view, "#{unit} option", "bag")
      refute has_element?(view, "#{unit} option", "No unit")

      # A kind with no standard unit has each unit, and no unit.
      view
      |> form("#measurement", measurement: %{measure_kind_id: lists.measure_kind.temperature})
      |> render_change()

      assert has_element?(view, "#{unit} option", "bag")
      assert has_element?(view, "#{unit} option", "No unit")
      refute has_element?(view, "#{unit}[required]")
    end

    test "with a retired standard unit still needs a unit, and offers the others", context do
      lists = context.lists
      admin = [actor: context.administrator, tenant: context.organisation]
      unit = "#measurement select[name='measurement[unit_id]']"
      standard!(context, :g)
      {:ok, _} = Rescord.Lists.retire_value(:unit, lists.unit.g, admin)

      {view, _html} = open(context.conn, context.path)

      view
      |> form("#measurement", measurement: %{measure_kind_id: lists.measure_kind.weight})
      |> render_change()

      assert has_element?(view, "#{unit}[required] option", "kg")
      refute has_element?(view, "#{unit} option[value='#{lists.unit.g}']")
      refute has_element?(view, "#{unit} option", "bag")
      refute has_element?(view, "#{unit} option", "No unit")
    end

    test "records another unit of the same sort as the person typed it", context do
      lists = context.lists
      standard!(context, :g)
      {view, _html} = open(context.conn, context.path)

      view
      |> form("#measurement", measurement: %{measure_kind_id: lists.measure_kind.weight})
      |> render_change()

      {:ok, view, _html} =
        view
        |> form("#measurement",
          measurement: %{
            measure_kind_id: lists.measure_kind.weight,
            value: "1.095",
            unit_id: lists.unit.kg
          }
        )
        |> render_submit()
        |> follow_redirect(context.conn, again(context, :weight))

      assert has_element?(view, "p[data-figure] strong", "1,095 g")

      {:ok, [entry]} = Journal.entries(context.biscuit.id, context.options)
      assert Decimal.equal?(entry.measurement.value, Decimal.new("1.095"))
      assert entry.measurement.unit_id == lists.unit.kg
    end

    test "says why the journal refused a unit that the form did not offer", context do
      lists = context.lists
      standard!(context, :g)
      {view, _html} = open(context.conn, context.path)

      html =
        render_submit(view, "record", %{
          "measurement" => %{
            "measure_kind_id" => lists.measure_kind.weight,
            "value" => "2",
            "unit_id" => lists.unit.bag
          }
        })

      assert html =~ "Unit is not a unit that Rescord converts to g, the unit of this kind"
      assert {:ok, []} = Journal.entries(context.biscuit.id, context.options)
    end

    test "puts each member of a group in that unit", context do
      crumpet = resident!(context.lists, context.options, %{name: "Crumpet"})

      group =
        Residents.form_group!(
          %{name: "The spring litter", resident_ids: [context.biscuit.id, crumpet.id]},
          context.options
        )

      measure!(context, context.biscuit, :weight, "0.915", :kg, 1)
      measure!(context, crumpet, :weight, "1095", :g, 2)
      standard!(context, :g)

      {view, _html} = open(context.conn, "#{context.base}/groups/#{group.id}/measurements")

      assert has_element?(view, "ul[data-multiples] strong", "915 g")
      assert has_element?(view, "ul[data-multiples] strong", "1,095 g")
      assert has_element?(view, "p[data-scale]", "Weight in g.")
    end
  end

  describe "the page of a resident" do
    test "has the newest value of each kind with a sparkline, and a link to the measurements",
         context do
      weights!(context)
      measure!(context, context.biscuit, :temperature, "38.5", nil, 2)

      {view, _html} = open(context.conn, "#{context.base}/residents/#{context.biscuit.id}")

      assert has_element?(view, "dl[data-measures] dt", "Weight")
      assert has_element?(view, "dl[data-measures] dd", "915 g, #{date(context, 0)}")
      assert has_element?(view, "dl[data-measures] dd [data-change=up]", "45 g more")
      assert has_element?(view, "dl[data-measures] dd svg[data-spark][aria-hidden=true]")
      # One measurement has no line and no change.
      assert has_element?(view, "dl[data-measures] dd", "38.5, #{date(context, 2)}")

      assert view
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("svg[data-spark]")
             |> Enum.count() == 1

      assert has_element?(view, "a[href='#{context.path}']", "Measurements")
    end

    test "with no measurement says so, and links to the page to record one", context do
      {view, html} = open(context.conn, "#{context.base}/residents/#{context.biscuit.id}")

      assert html =~ "No weight or other measurement yet."
      assert has_element?(view, "a[href='#{context.path}']", "Measurements")
    end
  end

  describe "the measurements of a group" do
    setup context do
      pig = fn name -> resident!(context.lists, context.options, %{name: name}) end
      crumpet = pig.("Crumpet")
      scone = pig.("Scone")
      anzac = pig.("Anzac")

      group =
        Residents.form_group!(
          %{
            name: "The spring litter",
            resident_ids: [context.biscuit.id, crumpet.id, scone.id, anzac.id]
          },
          context.options
        )

      {:ok,
       crumpet: crumpet,
       scone: scone,
       anzac: anzac,
       group: group,
       group_path: "#{context.base}/groups/#{group.id}/measurements"}
    end

    defp litter_weights!(context) do
      for {resident, values, unit} <- [
            {context.biscuit, ~w(690 760 915), :g},
            {context.crumpet, ~w(0.765 0.89 1.095), :kg},
            {context.scone, ~w(700 850 930), :g}
          ],
          {value, days_ago} <- Enum.zip(values, [14, 7, 1]) do
        measure!(context, resident, :weight, value, unit, days_ago)
      end
    end

    test "has a link on the page of the group", context do
      {view, _html} = open(context.conn, "#{context.base}/groups/#{context.group.id}")
      assert has_element?(view, "a[href='#{context.group_path}']", "Measurements")
    end

    test "with no measurement says so", context do
      {view, html} = open(context.conn, context.group_path)

      assert html =~ "Measurements of The spring litter"
      assert html =~ "No resident in the group has a measurement yet."
      refute has_element?(view, "ul[data-multiples]")
      refute has_element?(view, "nav[data-choice]")
    end

    test "has a tile for each member, with its newest value and its change", context do
      litter_weights!(context)
      {view, _html} = open(context.conn, context.group_path)

      tiles =
        view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query("ul[data-multiples] > li")

      assert Enum.count(tiles) == 4

      # The members are in the order of their names.
      assert tiles |> Enum.map(&(&1 |> LazyHTML.query("a") |> LazyHTML.text() |> String.trim())) ==
               ["Anzac", "Biscuit", "Crumpet", "Scone"]

      biscuit = "ul[data-multiples] > li:nth-child(2)"
      assert has_element?(view, "#{biscuit} strong", "915 g")
      assert has_element?(view, "#{biscuit} [data-change=up]", "155 g more")
      assert has_element?(view, "#{biscuit} svg[data-spark][aria-hidden=true]")

      assert has_element?(
               view,
               "#{biscuit} a[href='#{context.base}/residents/#{context.biscuit.id}/measurements?range=all']"
             )

      # A member with no measurement of the kind has a tile that says so.
      assert has_element?(view, "ul[data-multiples] > li:nth-child(1) small", "No measurement")
      refute has_element?(view, "ul[data-multiples] > li:nth-child(1) svg")
    end

    test "puts each member in one unit and on one scale, and says the scale", context do
      litter_weights!(context)
      {view, _html} = open(context.conn, context.group_path)

      # Crumpet was weighed in kg, and the newest measurement of the group is in g.
      crumpet = "ul[data-multiples] > li:nth-child(3)"
      assert has_element?(view, "#{crumpet} strong", "1,095 g")
      assert has_element?(view, "#{crumpet} [data-change=up]", "205 g more")

      assert has_element?(
               view,
               "p[data-scale]",
               "Weight in g. Each chart is from 600 g to 1,100 g, and from #{date(context, 14)} to #{date(context, 1)}."
             )

      # The line of a member is in front of the lines of the two others.
      html = view |> element(crumpet) |> render()
      assert html |> String.split("data-context") |> length() == 3
      assert html |> String.split("data-line") |> length() == 2
    end

    test "has a member in a unit that does not convert with its value and no chart", context do
      litter_weights!(context)
      measure!(context, context.anzac, :weight, "3", :bag, 2)

      {view, _html} = open(context.conn, context.group_path)

      anzac = "ul[data-multiples] > li:nth-child(1)"
      assert has_element?(view, "#{anzac} strong", "3 bag")
      assert has_element?(view, "#{anzac} small", "In another unit, so not in a chart")
      refute has_element?(view, "#{anzac} svg[data-spark]")

      # The others do not draw it.
      html = view |> element("ul[data-multiples] > li:nth-child(2)") |> render()
      assert html |> String.split("data-context") |> length() == 3
    end

    test "shows the kind with the most measurements, and another one that the person chooses",
         context do
      litter_weights!(context)
      measure!(context, context.scone, :temperature, "38.5", nil, 3)
      measure!(context, context.scone, :temperature, "39.1", nil, 2)
      kinds = context.lists.measure_kind

      {view, _html} = open(context.conn, context.group_path)

      assert has_element?(
               view,
               "#kind select option[selected][value='#{kinds.weight}']",
               "Weight"
             )

      assert has_element?(view, "p[data-scale]", "Weight in g.")

      view |> form("#kind", %{kind: kinds.temperature}) |> render_change()
      assert_patch(view, context.group_path <> "?kind=#{kinds.temperature}")

      assert has_element?(view, "p[data-scale]", "Temperature. Each chart is from 38.4 to 39.2")
      assert has_element?(view, "ul[data-multiples] > li:nth-child(4) strong", "39.1")
      assert has_element?(view, "ul[data-multiples] > li:nth-child(2) small", "No measurement")

      # A kind that the page does not know is the one with the most measurements.
      {view, _html} = open(context.conn, context.group_path <> "?kind=#{Ash.UUID.generate()}")
      assert has_element?(view, "p[data-scale]", "Weight in g.")
    end

    test "has no choice of the kind when the members have one kind", context do
      litter_weights!(context)
      {view, _html} = open(context.conn, context.group_path)

      refute has_element?(view, "#kind")
      assert has_element?(view, "nav[data-choice] a[aria-current=true]", "All")
    end

    test "shows the points of the time range, and keeps the newest value", context do
      litter_weights!(context)
      measure!(context, context.anzac, :weight, "500", :g, 100)
      kind = context.lists.measure_kind.weight

      {view, _html} = open(context.conn, context.group_path)
      view |> element("nav[data-choice] a", "30 days") |> render_click()
      assert_patch(view, context.group_path <> "?kind=#{kind}&range=30")

      # Anzac has no point in the range: the tile has the value and no line.
      anzac = "ul[data-multiples] > li:nth-child(1)"
      assert has_element?(view, "#{anzac} strong", "500 g")
      refute has_element?(view, "#{anzac} svg[data-spark]")
      assert has_element?(view, "p[data-scale]", "from #{date(context, 14)} to")

      # The link of a tile keeps the range.
      assert has_element?(
               view,
               "#{anzac} a[href='#{context.base}/residents/#{context.anzac.id}/measurements?range=30']"
             )
    end

    test "a group with no member says so", context do
      for member <-
            Residents.group_with_facts(context.group.id, context.options)
            |> elem(1)
            |> Map.fetch!(:members) do
        Residents.leave_group!(member, context.options)
      end

      {_view, html} = open(context.conn, context.group_path)
      assert html =~ "The group has no resident yet."
    end
  end
end
