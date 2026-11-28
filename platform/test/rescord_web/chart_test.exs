defmodule RescordWeb.ChartTest do
  @moduledoc """
  Holds the geometry of a chart (ADR 0080): round ticks that hold each
  value, and the place of each point as a percentage.
  """

  use ExUnit.Case, async: true

  alias RescordWeb.Chart

  doctest Chart

  defp ticks(least, greatest, whole? \\ false) do
    Decimal.new(least)
    |> Chart.ticks(Decimal.new(greatest), whole?)
    |> Enum.map(&Decimal.to_string(&1, :normal))
  end

  defp point(id, at, value), do: %{id: id, at: at, value: Decimal.new(value)}

  describe "the ticks" do
    test "are round numbers that hold the least and the greatest value" do
      assert ticks("310", "1095") == ~w(0 250 500 750 1000 1250)
      assert ticks("98", "104") == ~w(98 100 102 104)
      assert ticks("0.87", "1.095") == ~w(0.85 0.9 0.95 1 1.05 1.1)
      assert ticks("12000", "45500") == ~w(0 10000 20000 30000 40000 50000)
      assert ticks("0.000013", "0.000019") == ~w(0.000012 0.000014 0.000016 0.000018 0.00002)
    end

    test "start at zero when the least value is at most half of the greatest" do
      assert hd(ticks("310", "1095")) == "0"
      assert hd(ticks("5", "10")) == "0"
      assert hd(ticks("6", "10")) == "6"
      assert ticks("37.9", "39.4") == ~w(37.5 38 38.5 39 39.5)
    end

    test "hold a value below zero" do
      assert ticks("-3", "4") == ~w(-4 -2 0 2 4)
      assert ticks("-12", "-7") == ~w(-12 -11 -10 -9 -8 -7)
    end

    test "are there for one value, and for zero" do
      assert ticks("4", "4") == ~w(2 3 4 5 6)
      assert ticks("0", "0") == ~w(-0.5 -0.25 0 0.25 0.5)
      assert ticks("38.5", "38.5") |> List.first() |> Decimal.new() |> Decimal.lt?("38.5")
    end

    test "are whole numbers for a series of whole numbers" do
      assert ticks("3", "5") == ~w(3 3.5 4 4.5 5)
      assert ticks("3", "5", true) == ~w(3 4 5)
      assert ticks("1", "1", true) == ~w(0 1 2)
      assert ticks("5", "9", true) == ~w(5 6 7 8 9)
    end

    test "are three to six, and exact, for many ranges" do
      for least <- [0, 1, 7, 13, 99, 250, 999, 12_345],
          spread <- ["0.003", "0.7", "1", "4", "9", "37", "150", "1001", "86400"] do
        least = Decimal.new(least)
        greatest = Decimal.add(least, Decimal.new(spread))
        ticks = Chart.ticks(least, greatest)

        assert length(ticks) in 3..6
        assert Decimal.compare(List.first(ticks), least) != :gt
        assert Decimal.compare(List.last(ticks), greatest) != :lt

        # The steps are equal, and each tick is a short number.
        steps = Enum.zip_with(ticks, tl(ticks), &Decimal.sub(&2, &1))
        assert Enum.all?(steps, &Decimal.equal?(&1, hd(steps)))
        assert Enum.all?(ticks, &(String.length(Decimal.to_string(&1, :normal)) <= 12))
      end
    end
  end

  describe "the scale" do
    test "has the ticks of the values and the first and the last instant" do
      scale =
        Chart.scale([
          point("b", ~U[2026-11-28 09:00:00Z], "1095"),
          point("a", ~U[2026-10-03 09:00:00Z], "310")
        ])

      assert scale.from == ~U[2026-10-03 09:00:00Z]
      assert scale.to == ~U[2026-11-28 09:00:00Z]
      assert Decimal.equal?(List.last(scale.ticks), 1250)
    end

    test "is not there for no point" do
      assert Chart.scale([]) == nil
    end

    test "has whole ticks for whole values, and not for others" do
      at = ~U[2026-10-03 09:00:00Z]
      whole = Chart.scale([point("a", at, "3"), point("b", at, "5.0")])
      assert Enum.map(whole.ticks, &Decimal.to_string(&1, :normal)) == ~w(3 4 5)

      parts = Chart.scale([point("a", at, "3"), point("b", at, "4.5")])
      assert Enum.map(parts.ticks, &Decimal.to_string(&1, :normal)) == ~w(3 3.5 4 4.5)
    end
  end

  describe "the marks" do
    setup do
      points = [
        point("a", ~U[2026-11-01 00:00:00Z], "0"),
        point("b", ~U[2026-11-02 00:00:00Z], "250"),
        point("c", ~U[2026-11-05 00:00:00Z], "1000")
      ]

      {:ok, points: points, scale: Chart.scale(points)}
    end

    test "place the time from left to right and the value from the top down", context do
      assert [a, b, c] = Chart.marks(context.points, context.scale)

      assert {a.x, a.y} == {0.0, 100.0}
      assert {b.x, b.y} == {25.0, 75.0}
      assert {c.x, c.y} == {100.0, 0.0}
      assert Enum.map([a, b, c], & &1.id) == ["a", "b", "c"]
    end

    test "give each point the band of the plot that is nearest to it", context do
      assert [a, b, c] = Chart.marks(context.points, context.scale)

      assert {a.band_x, a.band_width} == {0.0, 12.5}
      assert {b.band_x, b.band_width} == {12.5, 50.0}
      assert {c.band_x, c.band_width} == {62.5, 37.5}
      # The bands fill the plot, with no gap and no part twice.
      assert a.band_width + b.band_width + c.band_width == 100.0
    end

    test "say where the words of a point go, so they stay in the plot", context do
      assert [a, b, c] = Chart.marks(context.points, context.scale)
      assert {a.anchor, c.anchor} == {"start", "end"}
      assert b.anchor == "start"

      middle = Chart.marks([point("m", ~U[2026-11-03 00:00:00Z], "500")], context.scale)
      assert [%{anchor: "middle", x: 50.0}] = middle
    end

    test "place one instant in the middle" do
      points = [point("a", ~U[2026-11-01 00:00:00Z], "4")]

      assert [%{x: 50.0, y: 50.0, band_x: +0.0, band_width: 100.0}] =
               Chart.marks(points, Chart.scale(points))
    end

    test "place a point of another series on a shared scale", context do
      other = [%{at: ~U[2026-11-03 00:00:00Z], value: Decimal.new("625")}]
      assert [%{id: nil, x: 50.0, y: 37.5}] = Chart.marks(other, context.scale)
    end

    test "make the path of the line", context do
      marks = Chart.marks(context.points, context.scale)
      assert Chart.path(marks) == "M0 100L25 75L100 0"
      assert Chart.path([]) == ""
    end
  end
end
