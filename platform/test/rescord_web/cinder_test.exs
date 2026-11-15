defmodule RescordWeb.CinderTest do
  @moduledoc """
  Holds Cinder, `RescordWeb.CinderTheme` and `assets/css/layers/vendor.css`
  together (ADR 0014).

  Cinder writes Tailwind classes into its markup, and Rescord has no Tailwind.
  `vendor.css` gives a rule to each class that carries behaviour, and to each
  mark of the theme. A new release of Cinder can add a class that does
  something. This test then fails, and somebody reads what the class does.
  """

  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias RescordWeb.CinderFixtures.{Live, Row}
  alias RescordWeb.CinderTheme

  @endpoint RescordWeb.Endpoint

  # The classes that do something. Without a rule the page breaks: a list of
  # choices that never closes, a button that always shows.
  @behaviour_classes ~w(hidden invisible sr-only)

  # The names of the icons, which `vendor.css` draws.
  @icons ~w(hero-chevron-up hero-chevron-down hero-chevron-up-down hero-chevron-right)

  # The root of each layout, which scopes the class selectors of `vendor.css`.
  @roots ~w(cinder-table cinder-list cinder-grid)

  # Tailwind classes that only lay a part out. `vendor.css` lays the same part
  # out by its `data-key`, or by its place, so these have no rule. The grid
  # is one of them: `grid_columns` of Cinder does nothing here, and the grid
  # takes as many columns as fit.
  #
  # `opacity-75` and `animate-pulse` dim a part while a result loads. They
  # have no rule on purpose: dimmed text falls below a contrast of 4.5:1, and
  # the overlay of Cinder already says that a result loads.
  @layout_classes ~w(
    absolute contents cursor-pointer flex flex-1 inline-flex inset-y-0
    items-center justify-between left-0 pl-3 pointer-events-none relative
    select-none space-x-2 space-x-6 truncate z-10 !flex !flex-col
    w-4 h-4 ml-2 top-full right-0 mt-1 z-50
    grid-cols-1 md:grid-cols-2 lg:grid-cols-3
    opacity-75 animate-pulse
    group/cinder-filter group/cinder-filters
    group-data-[cinder-partial]/cinder-filter:visible
    group-data-[cinder-partial]/cinder-filters:visible
  )

  setup do
    for {name, kind} <- [{"Biscuit", :dog}, {"Mango", :cat}, {"Pepper", :dog}] do
      Row
      |> Ash.Changeset.for_create(:create, %{name: name, kind: kind, desexed: true})
      |> Ash.create!()
    end

    on_exit(fn -> Ash.DataLayer.Ets.stop(Row) end)
  end

  defp markup(shape) do
    {:ok, view, _html} = live_isolated(build_conn(), Live, session: %{"shape" => shape})
    view |> render_async() |> LazyHTML.from_fragment()
  end

  defp classes(markup) do
    markup
    |> LazyHTML.query("[class]")
    |> Enum.flat_map(&LazyHTML.attribute(&1, "class"))
    |> Enum.flat_map(&String.split/1)
    |> Enum.uniq()
  end

  defp vendor_css, do: File.read!("assets/css/layers/vendor.css")

  describe "the theme" do
    test "sets each class to nothing, except its marks" do
      theme = CinderTheme.resolve_theme()
      marks = CinderTheme.marks()

      classes =
        for {key, value} <- theme,
            String.ends_with?(Atom.to_string(key), "_class"),
            do: {key, value}

      assert length(classes) > 100

      for {key, value} <- classes do
        assert value == Map.get(marks, key, ""), "the theme sets #{key} to #{inspect(value)}"
      end
    end

    test "has each key of the default theme of Cinder" do
      assert Cinder.Theme.complete_default()
             |> Map.keys()
             |> Enum.reject(&Map.has_key?(CinderTheme.resolve_theme(), &1)) == []
    end

    test "is the theme that Cinder takes when a collection names none" do
      assert Cinder.Theme.get_default_theme() == CinderTheme
    end
  end

  describe "the markup of Cinder" do
    for shape <- ~w(table list grid) do
      test "shows the rows as a #{shape}, with no class that vendor.css does not know" do
        markup = markup(unquote(shape))
        found = classes(markup)

        # Positive controls: a page of rows is there, and so are the classes of
        # Cinder. The rows have no order, so any one of the names will do.
        assert Enum.any?(~w(Biscuit Mango Pepper), &(LazyHTML.text(markup) =~ &1))
        assert "cinder-#{unquote(shape)}" in found
        assert "hidden" in found

        known =
          @behaviour_classes ++
            @icons ++ @roots ++ @layout_classes ++ Map.values(CinderTheme.marks())

        assert found -- known == []
      end
    end

    test "marks its parts with data-key, which vendor.css selects" do
      keys =
        markup("table")
        |> LazyHTML.query("[data-key]")
        |> Enum.flat_map(&LazyHTML.attribute(&1, "data-key"))

      for key <-
            ~w(container_class filter_container_class table_wrapper_class pagination_container_class) do
        assert key in keys
        assert vendor_css() =~ ~s([data-key="#{key}"])
      end
    end
  end

  describe "vendor.css" do
    test "has a rule for each class of Cinder that carries behaviour, and for each icon" do
      css = vendor_css()

      for class <- @behaviour_classes ++ @icons do
        assert css =~ ".#{class}", "vendor.css has no rule for .#{class}"
      end
    end

    test "has a rule for each mark of the theme" do
      css = vendor_css()

      for class <- CinderTheme.marks() |> Map.values() |> Enum.uniq(), class != "arrow" do
        assert css =~ ".#{class}", "vendor.css has no rule for .#{class}"
      end
    end
  end
end
