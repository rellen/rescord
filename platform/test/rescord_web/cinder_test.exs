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

  describe "the sort of a table column" do
    # `assets/js/cinder_tables.ts` makes the sort control a button, and gives
    # the header cell `aria-sort` (ADR 0017). It finds both by the markup of
    # Cinder, and reads the direction from the class of the icon.
    @control ~s([data-key="th_class"] > [phx-click="toggle_sort"])

    defp sort_icons(html) do
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(~s(#{@control}[phx-value-key="name"] [class*="hero-chevron"]))
      |> Enum.flat_map(&LazyHTML.attribute(&1, "class"))
      |> Enum.flat_map(&String.split/1)
      |> Enum.filter(&String.starts_with?(&1, "hero-chevron"))
    end

    test "is the element, and has the icons, that cinder_tables.ts reads" do
      {:ok, view, _html} = live_isolated(build_conn(), Live, session: %{"shape" => "table"})
      html = render_async(view)

      # The fixture has two columns that sort.
      assert html |> LazyHTML.from_fragment() |> LazyHTML.query(@control) |> Enum.count() == 2
      assert sort_icons(html) == ["hero-chevron-up-down"]

      control = element(view, ~s(#{@control}[phx-value-key="name"]))

      render_click(control)
      assert view |> render_async() |> sort_icons() == ["hero-chevron-up"]

      render_click(control)
      assert view |> render_async() |> sort_icons() == ["hero-chevron-down"]
    end

    test "cinder_tables.ts names that element and those icons, and app.js calls it" do
      module = File.read!("assets/js/cinder_tables.ts")

      for text <- [
            ~s('[data-key="th_class"]'),
            ~s('[phx-click="toggle_sort"]'),
            ~s(".hero-chevron-up"),
            ~s(".hero-chevron-down")
          ] do
        assert module =~ text, "cinder_tables.ts does not name #{text}"
      end

      # The code of app.js, with no comment line.
      code =
        "assets/js/app.js"
        |> File.read!()
        |> String.split("\n")
        |> Enum.reject(&String.starts_with?(String.trim_leading(&1), "//"))
        |> Enum.join("\n")

      # Without the first, a patch takes the focus off a sort control.
      # The page keeps a table, and a <details>, before each update (ADR 0031).
      assert code =~ "onBeforeElUpdated: (from, to) => {"
      assert code =~ "keepCinderTables(from, to)"
      assert code =~ "keepDetailsOpen(from, to)"
      assert code =~ "onPatchEnd: () => enhanceCinderTables()"
      assert code =~ "listenToCinderTables()"
    end
  end

  describe "the other controls of a collection" do
    # `assets/js/cinder_tables.ts` also says what a button that opens a list
    # is, names the buttons and the table, and says the count of a result
    # (ADR 0087). It finds each part by the markup of Cinder. Each selector
    # here is in the module, word for word.
    @parts [
      # A choice filter: the button, then its list of radio buttons.
      ~s([data-key="filter_select_input_class"]),
      ~s([data-key="filter_select_dropdown_class"]),
      # The size of a page: the button, then its list, between the words.
      ~s([data-key="page_size_dropdown_class"]),
      ~s([data-key="page_size_dropdown_container_class"]),
      ~s([data-key="page_size_container_class"]),
      ~s([data-key="page_size_label_class"]),
      # The pages.
      ~s([data-key="pagination_nav_class"]),
      ~s([data-key="pagination_current_class"]),
      ~s([data-key="pagination_info_class"]),
      # The collection, a filter, and the button that clears it.
      ~s([data-key="container_class"]),
      ~s([data-key="filter_input_wrapper_class"]),
      ~s([data-key="filter_clear_button_class"])
    ]

    defp count(markup, selector), do: markup |> LazyHTML.query(selector) |> Enum.count()

    test "are the elements that cinder_tables.ts reads" do
      markup = markup("table")

      for part <- @parts do
        assert count(markup, part) > 0, "Cinder renders no #{part}"
      end

      # The list of a button is the next element, and has an id.
      for {button, list} <- [
            {"filter_select_input_class", "filter_select_dropdown_class"},
            {"page_size_dropdown_class", "page_size_dropdown_container_class"}
          ] do
        assert count(markup, ~s([data-key="#{button}"])) ==
                 count(markup, ~s([data-key="#{button}"] + [id][data-key="#{list}"]))
      end

      # A choice filter: its button has an id, a label names that id, and
      # its choices are radio buttons.
      [id | _] =
        markup
        |> LazyHTML.query(~s([data-key="filter_select_input_class"]))
        |> LazyHTML.attribute("id")

      assert count(markup, ~s(label[for="#{id}"])) == 1
      assert count(markup, ~s([data-key="filter_select_dropdown_class"] input[type="radio"])) > 1

      # The words of a button with a sign are in its title.
      assert count(markup, ~s|[data-key="filter_clear_button_class"]:not([title])|) == 0
      assert count(markup, ~s|[data-key="pagination_nav_class"] button:not([title])|) == 0

      # A filter has a label, which says what its clear button clears.
      assert count(markup, ~s([data-key="filter_input_wrapper_class"] label)) > 0

      # A row has the id of its record, which the count of a result reads.
      assert count(markup, "tbody tr[data-item-id]") == 2
    end

    test "say that a collection loads, and that it has nothing" do
      # A test reads with no task (`disable_async?`), so no page of a test
      # shows the overlay. The theme of Cinder has its key, and the renderers
      # write the key of a part as its `data-key`.
      assert Map.has_key?(Cinder.Theme.complete_default(), :loading_overlay_class)

      {:ok, view, _html} = live_isolated(build_conn(), Live, session: %{"shape" => "table"})
      render_async(view)

      view
      |> element("#rows-filter-form")
      |> render_change(%{"filters" => %{"name" => "no row has this name"}})

      nothing = view |> render_async() |> LazyHTML.from_fragment()
      assert count(nothing, ~s([data-key="empty_class"])) == 1
      assert count(nothing, "tbody tr[data-item-id]") == 0
    end

    test "cinder_tables.ts names each part, app.js starts it, and vendor.css hides the status" do
      module = File.read!("assets/js/cinder_tables.ts")

      for part <-
            @parts ++
              [
                ~s([data-key="loading_overlay_class"]),
                ~s([data-key="empty_class"]),
                "[data-item-id]",
                ~s(input[type="radio"]),
                "button[title]"
              ] do
        assert module =~ part, "cinder_tables.ts does not name #{part}"
      end

      app = File.read!("assets/js/app.js")

      # Without the first, a button does not say that its list opened. Without
      # the second, an arrow key closes the list of a choice filter.
      assert app =~ "\nwatchCinderLists()\n"
      assert app =~ "\nholdCinderListsOpen()\n"

      assert module =~ "[data-cinder-status]"
      assert vendor_css() =~ "[data-cinder-status] {"
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
