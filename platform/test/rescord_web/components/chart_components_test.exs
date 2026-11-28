defmodule RescordWeb.ChartComponentsTest do
  # The markup contract of a chart (ADR 0080): an image with a name and a
  # description, places as percentages, no class, no colour and no style,
  # and points that answer.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import RescordWeb.ChartComponents

  defp parse(html), do: LazyHTML.from_fragment(html)

  defp attribute(doc, selector, name),
    do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  defp points(count) do
    for n <- 1..count do
      %{
        id: "p#{n}",
        at: DateTime.add(~U[2026-11-01 08:00:00Z], n, :day),
        value: Decimal.new(300 + n * 10),
        label: "Day #{n}: #{300 + n * 10} g"
      }
    end
  end

  defp chart(points, extra \\ []) do
    render_component(
      &line_chart/1,
      [
        id: "weight",
        title: "Weight of Biscuit, in g",
        summary: "3 measurements.",
        points: points,
        from: "2 November 2026",
        to: "4 November 2026"
      ] ++ extra
    )
  end

  describe "a line chart" do
    test "is one image with a name, and its description is the caption of the figure" do
      doc = points(3) |> chart() |> parse()

      assert attribute(doc, "figure[data-chart] svg[role=img]", "aria-label") ==
               ["Weight of Biscuit, in g"]

      assert attribute(doc, "svg[role=img]", "aria-describedby") == ["weight-summary"]

      assert doc |> LazyHTML.query("figcaption#weight-summary") |> LazyHTML.text() ==
               "3 measurements."

      # No part of the chart takes the focus of the keyboard.
      assert attribute(doc, "svg[role=img]", "focusable") == ["false"]
      assert count(doc, "[tabindex]") == 0
    end

    test "hides its axes and its points from a screen reader" do
      doc = points(3) |> chart() |> parse()

      assert attribute(doc, "ol[data-ticks]", "aria-hidden") == ["true"]
      assert attribute(doc, "p[data-span]", "aria-hidden") == ["true"]
      assert attribute(doc, "g[data-points]", "aria-hidden") == ["true"]
    end

    test "has no class, no style and no colour: the stylesheet has the look" do
      html = chart(points(3), pick: "pick", selected: "p2")

      refute html =~ ~r/\sclass=/
      refute html =~ ~r/\sstyle=/
      refute html =~ ~r/\s(fill|stroke)=/
      refute html =~ ~r/#[0-9a-fA-F]{3,8}\b/
    end

    test "writes each place as a percentage, and has no viewBox of its own" do
      doc = points(3) |> chart() |> parse()

      assert attribute(doc, "svg[role=img]", "viewBox") == []
      assert attribute(doc, "[data-dots] circle", "cx") == ["0.0%", "50.0%", "100.0%"]
      assert attribute(doc, "[data-dots] circle", "r") == ["4", "4", "4"]
      # Only the line stretches.
      assert attribute(doc, "svg[role=img] > svg", "preserveAspectRatio") == ["none"]
      assert [path] = attribute(doc, "path[data-line]", "d")
      assert path =~ ~r/^M0 [\d.]+L50 [\d.]+L100 [\d.]+$/
    end

    test "has the numbers of the ticks from the top down, and the two dates" do
      doc = points(3) |> chart() |> parse()

      ticks = doc |> LazyHTML.query("ol[data-ticks] > li") |> Enum.map(&LazyHTML.text/1)
      assert ticks == Enum.sort_by(ticks, &String.to_integer/1, :desc)
      assert count(doc, "[data-grid] line") == length(ticks)

      assert doc |> LazyHTML.query("p[data-span] > span") |> Enum.map(&LazyHTML.text/1) ==
               ["2 November 2026", "4 November 2026"]
    end

    test "writes the number of a tick with the function of the page" do
      doc = points(3) |> chart(tick: &"#{Decimal.to_string(&1, :normal)} g") |> parse()

      assert doc
             |> LazyHTML.query("ol[data-ticks] > li")
             |> Enum.all?(&(LazyHTML.text(&1) =~ " g"))
    end

    test "each point answers a press with its id, and has its words" do
      doc = points(3) |> chart(pick: "pick") |> parse()

      assert attribute(doc, "[data-points] > g", "phx-click") == ["pick", "pick", "pick"]
      assert attribute(doc, "[data-points] > g", "phx-value-point") == ["p1", "p2", "p3"]
      assert count(doc, "[data-points] > g > rect") == 3

      assert doc |> LazyHTML.query("[data-points] text") |> Enum.map(&LazyHTML.text/1) ==
               ["Day 1: 310 g", "Day 2: 320 g", "Day 3: 330 g"]

      # The words of a point at an edge stay in the plot.
      assert attribute(doc, "[data-points] text", "text-anchor") == ["start", "middle", "end"]
    end

    test "marks the point that the person chose" do
      doc = points(3) |> chart(pick: "pick", selected: "p2") |> parse()

      assert count(doc, "[data-points] > g[data-selected]") == 1
      assert attribute(doc, "[data-points] > g[data-selected]", "phx-value-point") == ["p2"]
    end

    test "with no event, a point has its words for a pointer and takes no press" do
      doc = points(3) |> chart() |> parse()

      assert count(doc, "[data-points] > g") == 3
      assert count(doc, "[phx-click]") == 0
      assert count(doc, "[phx-value-point]") == 0
    end

    test "with many points, draws the line and the newest dot alone" do
      doc = points(41) |> chart(pick: "pick") |> parse()

      assert count(doc, "[data-dots]") == 0
      assert count(doc, "circle[data-newest]") == 1
      assert count(doc, "[data-points] > g") == 41

      doc = points(40) |> chart() |> parse()
      assert count(doc, "[data-dots] circle") == 40
      assert count(doc, "circle[data-newest]") == 0
    end

    test "with very many points, no point answers" do
      doc = points(121) |> chart(pick: "pick") |> parse()

      assert count(doc, "[data-points]") == 0
      assert count(doc, "[phx-click]") == 0
      assert count(doc, "path[data-line]") == 1
    end

    test "draws other series behind, on the same scale" do
      others = [Enum.map(points(3), &Map.delete(&1, :id)), Enum.take(points(3), 2)]
      doc = points(3) |> chart(context: others) |> parse()

      assert count(doc, "path[data-context]") == 2
      # The series of the chart is the last path, so it is in front.
      assert doc |> LazyHTML.query("svg[role=img] > svg > path") |> Enum.count() == 3

      assert doc
             |> LazyHTML.query("svg[role=img] > svg > path")
             |> Enum.at(2)
             |> LazyHTML.attribute("data-line") == [""]
    end

    test "escapes the words that it is given" do
      [point] = points(1)

      html =
        chart([%{point | label: "<script>alert(1)</script>"}],
          title: "\"><script>",
          summary: "<b>bold</b>"
        )

      refute html =~ "<script>"
      refute html =~ "<b>"
    end
  end

  describe "a sparkline" do
    test "is decoration: a screen reader does not see it" do
      doc = render_component(&sparkline/1, points: points(5)) |> parse()

      assert attribute(doc, "svg[data-spark]", "aria-hidden") == ["true"]
      assert attribute(doc, "svg[data-spark]", "focusable") == ["false"]
      assert count(doc, "path[data-line]") == 1
      # One dot: the newest value.
      assert attribute(doc, "svg[data-spark] > circle", "cx") == ["100.0%"]
    end

    test "has no class, no style and no colour" do
      html = render_component(&sparkline/1, points: points(5), context: [points(3)])

      refute html =~ ~r/\sclass=/
      refute html =~ ~r/\sstyle=/
      refute html =~ ~r/\s(fill|stroke)=/
    end

    test "draws nothing for no point, and a dot for one" do
      doc = render_component(&sparkline/1, points: []) |> parse()
      assert count(doc, "path") == 0
      assert count(doc, "circle") == 0

      doc = render_component(&sparkline/1, points: points(1)) |> parse()
      assert count(doc, "circle") == 1
    end

    test "takes a scale that several sparklines share" do
      scale = RescordWeb.Chart.scale(points(10))
      doc = render_component(&sparkline/1, points: points(5), scale: scale) |> parse()

      # The fifth of ten days is not at the right edge.
      assert attribute(doc, "svg[data-spark] > circle", "cx") == ["44.44%"]
    end
  end

  describe "a heat map (ADR 0116)" do
    defp heat(extra \\ []) do
      render_component(
        &heat_table/1,
        [
          id: "calendar",
          summary: "91% of 24 tasks were done on time.",
          corner: "Day of the week",
          columns: [
            %{label: "Jun", words: "Week of 1 June 2026"},
            %{label: "", words: "Week of 8 June 2026"}
          ],
          rows: [
            %{
              label: "Mon",
              words: "Monday",
              cells: [
                %{id: "2026-06-01", level: 4, words: "8 of 8 on time"},
                %{id: "2026-06-08", level: 2, words: "7 of 8 on time, 1 skipped", mark: true}
              ]
            },
            %{
              label: "Tue",
              words: "Tuesday",
              cells: [
                %{id: "2026-06-02", level: 0, words: "No task", today: true},
                %{level: :none, words: ""}
              ]
            }
          ]
        ] ++ extra
      )
    end

    test "is a table named by its caption, with a header for each row and column" do
      doc = heat() |> parse()

      assert doc |> LazyHTML.query("table > caption") |> LazyHTML.text() =~ "91% of 24 tasks"
      assert count(doc, "thead th[scope=col]") == 3
      assert count(doc, "tbody th[scope=row]") == 2

      # The short words show, and the whole words are for a screen reader.
      assert doc |> LazyHTML.query("thead th [data-words]") |> Enum.map(&LazyHTML.text/1) ==
               ["Day of the week", "Week of 1 June 2026", "Week of 8 June 2026"]

      assert attribute(doc, "tbody th > span[aria-hidden]", "aria-hidden") == ["true", "true"]
    end

    test "has a step, a dot and an outline as attributes, and the words of each cell" do
      doc = heat() |> parse()

      assert attribute(doc, "td", "data-level") == ["4", "2", "0", "none"]
      assert count(doc, "td[data-mark]") == 1
      assert count(doc, "td[data-today]") == 1

      assert doc |> LazyHTML.query("td > span") |> Enum.map(&LazyHTML.text/1) ==
               ["8 of 8 on time", "7 of 8 on time, 1 skipped", "No task"]
    end

    test "has cells that take a press, and no focus, with the chosen one marked" do
      doc = heat(pick: "pick", selected: "2026-06-08") |> parse()

      assert attribute(doc, "td[phx-click]", "phx-value-cell") ==
               ["2026-06-01", "2026-06-08", "2026-06-02"]

      assert attribute(doc, "td[data-selected]", "phx-value-cell") == ["2026-06-08"]
      assert count(doc, "[tabindex]") == 0

      doc = heat() |> parse()
      assert count(doc, "td[phx-click]") == 0
      assert count(doc, "td[data-selected]") == 0
    end

    test "has no class, no style and no colour" do
      html = heat(variant: "numbers")

      assert html =~ ~s(data-heat="numbers")
      refute html =~ ~r/\sclass=/
      refute html =~ ~r/\sstyle=/
    end
  end

  describe "a count over time (ADR 0117)" do
    test "draws steps, and a dashed rule at a value that the scale holds" do
      points = points(3)
      scale = RescordWeb.Chart.scale([%{hd(points) | value: Decimal.new(400)} | points])

      doc =
        chart(points, step: true, scale: scale, rules: [Decimal.new(400)])
        |> parse()

      [line] = attribute(doc, "path[data-line]", "d")
      assert line =~ ~r/^M0 [\d.]+H50V[\d.]+H100V[\d.]+$/
      assert attribute(doc, "line[data-rule]", "y1") == ["0.0%"]
    end
  end

  describe "bars above and below a line (ADR 0117)" do
    test "are one image with a name and a description, and a bar for each count" do
      doc =
        render_component(&updown_bars/1,
          id: "moves",
          title: "Arrivals and departures of each week",
          summary: "3 arrivals and 3 departures.",
          pairs: [{2, 0}, {1, 3}],
          from: "Week of 16 November 2026",
          to: "Week of 23 November 2026"
        )
        |> parse()

      assert attribute(doc, "svg[role=img]", "aria-label") == [
               "Arrivals and departures of each week"
             ]

      assert attribute(doc, "svg[role=img]", "aria-describedby") == ["moves-summary"]
      assert doc |> LazyHTML.query("#moves-summary") |> LazyHTML.text() =~ "3 arrivals"
      assert count(doc, "rect[data-up]") == 2
      assert count(doc, "rect[data-down]") == 1
      assert attribute(doc, "rect[data-down]", "height") == ["50.0%"]
    end
  end
end
