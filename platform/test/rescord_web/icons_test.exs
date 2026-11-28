defmodule RescordWeb.IconsTest do
  use ExUnit.Case, async: true

  alias RescordWeb.Icons

  test "each kind of journal entry has a shape, as an atom and as text" do
    for kind <- Rescord.Journal.EntryKind.values() do
      shape = Icons.entry_kind(kind)
      assert shape in Icons.names(), "the kind #{kind} has no shape"
      assert Icons.entry_kind(Atom.to_string(kind)) == shape
    end

    assert Icons.entry_kind("no such kind") == nil
  end

  test "each part of the site that the menu marks has a shape" do
    %{attrs: attrs} = RescordWeb.Layouts.__components__()[:app]
    sections = Enum.find(attrs, &(&1.name == :section)).opts[:values]

    for section <- sections, section != nil do
      assert Icons.section(section) in Icons.names(), "the part #{section} has no shape"
    end
  end

  test "each kind of stock movement has a shape" do
    for kind <- Rescord.Inventory.MovementKind.values() do
      assert Icons.movement(kind) in Icons.names(), "the movement #{kind} has no shape"
    end
  end

  test "a drawing keeps to the rules: no colour, no fill, no size of its own" do
    for name <- Icons.names() do
      drawing = Icons.drawing(name)
      refute drawing =~ ~r/\b(fill|stroke|style|class)=/, "#{name} sets its own look"
      assert drawing =~ ~r/^<(path|circle|rect|g) /, "#{name} is not an SVG drawing"
    end
  end

  test "the chevrons that Cinder asks for are the drawings of the module" do
    css = File.read!(Path.expand("../../assets/css/layers/vendor.css", __DIR__))

    for name <- ~w(chevron-up chevron-down chevron-up-down chevron-right) do
      encoded =
        name
        |> Icons.drawing()
        |> String.replace(~s("), "'")
        |> String.replace("<", "%3C")
        |> String.replace(">", "%3E")

      [_, rule] = Regex.run(~r/\.hero-#{name} \{\n  --shape: ([^\n]+)\n/, css)
      assert rule =~ encoded, "the mask of #{name} in vendor.css is not its drawing"
    end
  end
end
