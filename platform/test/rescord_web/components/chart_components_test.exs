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
end
