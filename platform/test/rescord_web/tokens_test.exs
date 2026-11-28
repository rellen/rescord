defmodule RescordWeb.TokensTest do
  @moduledoc """
  Holds the colours of `assets/css/layers/tokens.css` to WCAG AA, in the light
  and in the dark scheme (ADR 0015).

  A text and its ground need a contrast of 4.5 to 1. The edge of a control,
  the focus ring and an icon need 3 to 1. The pairs below are the ones that
  the stylesheet puts together. A new pair in a layer takes a line here.

  The test also holds the rule that only `tokens.css` writes a colour.
  """

  use ExUnit.Case, async: true

  import Bitwise

  @layers "assets/css/layers"

  # {foreground, ground, minimum}
  @text 4.5
  @edge 3.0

  @grounds ~w(bg surface raised selected)

  @pairs for(
           ground <- @grounds,
           text <- ~w(text muted link),
           do: {text, ground, @text}
         ) ++
           for(ground <- @grounds, edge <- ~w(field focus accent), do: {edge, ground, @edge}) ++
           for(
             ground <- ~w(surface selected),
             state <- ~w(ok alert info),
             do: {state, ground, @text}
           ) ++
           [
             {"on-accent", "accent", @text},
             {"on-bar", "bar", @text},
             {"accent", "bar", @text},
             {"ok", "ok-surface", @text},
             {"alert", "alert-surface", @text},
             {"info", "info-surface", @text},
             {"text", "ok-surface", @text},
             {"text", "alert-surface", @text},
             {"text", "info-surface", @text},
             {"text", "mark", @text},
             {"alert", "bg", @text},
             {"focus", "bar", @edge},
             # The words of a cell of a heat map, on each step of the ramp (ADR 0116).
             {"text", "heat-1", @text},
             {"text", "heat-2", @text},
             {"on-heat-3", "heat-3", @text},
             {"on-accent", "heat-4", @text}
           ]

  # A tint is a share of one colour over a ground: {foreground, {colour, share, ground}, minimum}.
  @tinted for(
            ground <- @grounds,
            text <- ~w(text muted link),
            do: {text, {"text", 0.06, ground}, @text}
          ) ++
            [{"accent", {"accent", 0.16, "bar"}, @text}]

  defp tokens do
    css = File.read!(Path.join(@layers, "tokens.css"))

    for [_, name, light, dark] <-
          Regex.scan(~r/--([a-z0-9-]+):\s*light-dark\((#[0-9a-f]{6}),\s*(#[0-9a-f]{6})\)/, css),
        into: %{} do
      {name, {rgb(light), rgb(dark)}}
    end
  end

  defp rgb("#" <> hex) do
    value = String.to_integer(hex, 16)
    {value >>> 16 &&& 0xFF, value >>> 8 &&& 0xFF, value &&& 0xFF}
  end

  defp luminance({r, g, b}) do
    [r, g, b] =
      for channel <- [r, g, b] do
        value = channel / 255
        if value <= 0.03928, do: value / 12.92, else: :math.pow((value + 0.055) / 1.055, 2.4)
      end

    0.2126 * r + 0.7152 * g + 0.0722 * b
  end

  defp contrast(one, other) do
    [low, high] = Enum.sort([luminance(one), luminance(other)])
    (high + 0.05) / (low + 0.05)
  end

  defp over({r, g, b}, share, {gr, gg, gb}) do
    mix = fn top, below -> round(top * share + below * (1 - share)) end
    {mix.(r, gr), mix.(g, gg), mix.(b, gb)}
  end

  defp scheme(tokens, name, 0), do: tokens |> Map.fetch!(name) |> elem(0)
  defp scheme(tokens, name, 1), do: tokens |> Map.fetch!(name) |> elem(1)

  test "the test reads the colours of tokens.css" do
    tokens = tokens()

    assert map_size(tokens) == 26
    assert tokens["bg"] == {rgb("#f1f7f5"), rgb("#0b1916")}
    # A positive control for the arithmetic: black on white is 21 to 1.
    assert_in_delta contrast({0, 0, 0}, {255, 255, 255}), 21.0, 0.001
    # And a pair that must fail, or the comparisons below prove nothing.
    assert contrast(scheme(tokens, "border", 0), scheme(tokens, "surface", 0)) < @edge
  end

  for {scheme, index} <- [light: 0, dark: 1] do
    test "each text, edge and ring meets its minimum on its ground, in the #{scheme} scheme" do
      tokens = tokens()

      failures =
        for {foreground, ground, minimum} <- @pairs,
            ratio =
              contrast(
                scheme(tokens, foreground, unquote(index)),
                scheme(tokens, ground, unquote(index))
              ),
            ratio < minimum do
          "#{foreground} on #{ground}: #{Float.round(ratio, 2)} to 1, below #{minimum}"
        end

      assert failures == []
    end

    test "each text meets its minimum on a tinted ground, in the #{scheme} scheme" do
      tokens = tokens()

      failures =
        for {foreground, {colour, share, ground}, minimum} <- @tinted,
            tinted =
              over(
                scheme(tokens, colour, unquote(index)),
                share,
                scheme(tokens, ground, unquote(index))
              ),
            ratio = contrast(scheme(tokens, foreground, unquote(index)), tinted),
            ratio < minimum do
          "#{foreground} on #{share} of #{colour} over #{ground}: #{Float.round(ratio, 2)} to 1, below #{minimum}"
        end

      assert failures == []
    end
  end

  test "no layer but tokens.css writes a colour" do
    files = Path.wildcard(Path.join(@layers, "*.css")) -- [Path.join(@layers, "tokens.css")]
    assert length(files) >= 5

    for file <- files do
      # Comments may name a colour; rules may not.
      rules = file |> File.read!() |> String.replace(~r{/\*.*?\*/}s, "")

      assert Regex.scan(~r/#[0-9a-fA-F]{3,8}\b|\b(?:rgb|rgba|hsl|hsla|oklch|oklab)\(/, rules) ==
               [],
             "#{file} writes a colour; add a token to tokens.css and read it"
    end
  end
end
