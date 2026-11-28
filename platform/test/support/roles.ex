defmodule RescordWeb.Roles do
  @moduledoc ~S"""
  Finds the parts of a page as a person with a screen reader does: by
  landmark, heading, role and accessible name, not by DOM id or CSS path
  (ADR 0107, issue 33). It sits on top of PhoenixTest.

  A test starts with `use RescordWeb.Roles` (a browser test:
  `use RescordWeb.Roles, browser: true`). That imports PhoenixTest, with
  `within/3`, `assert_has/2,3`, `refute_has/2,3` and `click/2` of this
  module, which take a locator or a CSS selector:

      conn
      |> visit(~p"/o/wattle-creek/inventory/#{item.id}")
      |> assert_has(main() |> heading(level: 1), text: "Meadow hay")
      |> click(region("Lots") |> button("Take off B-1"))
      |> within(region("New lot"), &fill_in(&1, "Quantity", with: "4"))
      |> refute_has(main() |> alert())

  A locator says what to find, and a pipe narrows it: `main/0`,
  `banner/0`, `contentinfo/0`, `navigation/1`, `region/1`,
  `complementary/1`, `article/1`, `heading/0..3`, `button/1`, `link/1`,
  `field/1`, `table/1`, `row/1`, `alert/0` and `status/0`.

  The queries `has?/2`, `all/2`, `one/2`, `text/2` and `names/2` read a
  session, the HTML of a controller or the HTML of a component.

  The accessible name is a short form of the W3C computation: the text of
  `aria-labelledby`, else `aria-label`, else the `<label>` of a field, else
  the `<caption>` of a table, else (for a button, a link, a heading or a
  row) the words of the element, leaving out what is `aria-hidden`. Spaces
  are folded, so an icon before a word does not count. A name is matched
  whole, or by a regex.

  An element that is `hidden`, or inside one, is not on the page, as in a
  browser. A closed `<details>` is still read: a LiveView test cannot open
  one, and its form is there in the HTML. In a browser test Playwright
  finds by role and name itself.
  """

  # A test support module may use any boundary, and any test may use it (ADR 0009).
  use Boundary, top_level?: true, check: [in: false, out: false]

  defstruct role: nil, name: nil, level: nil, scope: []

  @type name :: String.t() | Regex.t() | nil
  @type t :: %__MODULE__{role: atom, name: name, level: 1..6 | nil, scope: [t]}
  @type source :: Phoenix.LiveViewTest.View.t() | LazyHTML.t() | String.t()

  # The elements of each role, before the landmark and name tests.
  @css %{
    main: "main",
    # A header or footer inside these is not a landmark (HTML-AAM).
    banner: "header:not(article *, aside *, main *, nav *, section *)",
    contentinfo: "footer:not(article *, aside *, main *, nav *, section *)",
    navigation: "nav, [role=navigation]",
    region: "section, [role=region]",
    complementary: "aside",
    article: "article",
    heading: "h1, h2, h3, h4, h5, h6",
    button: "button, [role=button], input[type=submit], input[type=button]",
    link: "a[href]",
    field: "input:not([type=hidden]), select, textarea",
    table: "table",
    form: "form",
    figure: "figure",
    details: "details",
    definition: "dd",
    image: "img:not([alt=''])",
    row: "tr",
    list: "ul, ol, [role=list]",
    item: "li",
    alert: "[role=alert]",
    status: "[role=status], output"
  }

  # The roles named by their own words; the rest only by a label.
  @named_by_content [:button, :link, :heading, :row, :item]

  ## Locators

  @doc "The main landmark."
  def main(scope \\ nil), do: locate(scope, :main, nil)

  @doc "The banner: the site's header, not a header inside main or an article."
  def banner(scope \\ nil), do: locate(scope, :banner, nil)

  @doc "The contentinfo: the site's footer."
  def contentinfo(scope \\ nil), do: locate(scope, :contentinfo, nil)

  @doc "A navigation landmark, by its name."
  def navigation(scope \\ nil, name), do: locate(scope, :navigation, name)

  @doc "A region: a section with a name, mostly from its heading."
  def region(scope \\ nil, name), do: locate(scope, :region, name)

  @doc "A complementary landmark (an aside)."
  def complementary(scope \\ nil, name), do: locate(scope, :complementary, name)

  @doc "An article, by its name."
  def article(scope \\ nil, name), do: locate(scope, :article, name)

  @doc """
  A form, by its name: an `aria-label` or `aria-labelledby`. With `nil`,
  any form, as in `region("Stock") |> form(nil)`.
  """
  def form(scope \\ nil, name), do: locate(scope, :form, name)

  @doc "A table, by its name."
  def table(scope \\ nil, name), do: locate(scope, :table, name)

  @doc """
  A disclosure (`details`), by the name of its `summary`, as a person
  finds the form or the list that it holds: its `aria-label`, as on a
  confirm step (`<.confirm>`), or else its words.
  """
  def details(scope \\ nil, name), do: locate(scope, :details, name)

  @doc """
  The definition (`dd`) of a term (`dt`) of a description list, by the
  words of the term: `definition("In stock")`. The two are in one `div` of
  the `dl`, as `<.list>` draws them.
  """
  def definition(scope \\ nil, term), do: locate(scope, :definition, term)

  @doc "A figure, by its name: the words of its `figcaption`."
  def figure(scope \\ nil, name), do: locate(scope, :figure, name)

  @doc "An image, by its `alt`. An image with an empty `alt` is decoration, and is not found."
  def image(scope \\ nil, name), do: locate(scope, :image, name)

  @doc "A row of a table, by its words: give a regex, such as `row(~r/^Meadow hay/)`."
  def row(scope \\ nil, name), do: locate(scope, :row, name)

  @doc "A list (`ul` or `ol`), by its name: an `aria-label` or `aria-labelledby`."
  def list(scope \\ nil, name), do: locate(scope, :list, name)

  @doc """
  An item of a list, by its words: give a regex, such as `item(~r/^Biscuit/)`.
  ARIA gives an item no name, so a browser test finds it by its text.
  """
  def item(scope \\ nil, name), do: locate(scope, :item, name)

  @doc "A button, by its name."
  def button(scope \\ nil, name), do: locate(scope, :button, name)

  @doc "A link, by its name."
  def link(scope \\ nil, name), do: locate(scope, :link, name)

  @doc "A form field, by its label."
  def field(scope \\ nil, label), do: locate(scope, :field, label)

  @doc "An alert (`role=alert`) that shows, with any words."
  def alert(scope \\ nil), do: locate(scope, :alert, nil)

  @doc "A status message (`role=status` or `output`) that shows."
  def status(scope \\ nil), do: locate(scope, :status, nil)

  @doc """
  A heading. Give its name, its level, both or neither:

      heading("Lots")
      heading(level: 1)
      main() |> heading("Lots", level: 2)
  """
  def heading(), do: heading(nil, nil, [])
  def heading(%__MODULE__{} = scope), do: heading(scope, nil, [])
  def heading(opts) when is_list(opts), do: heading(nil, nil, opts)
  def heading(name), do: heading(nil, name, [])
  def heading(%__MODULE__{} = scope, opts) when is_list(opts), do: heading(scope, nil, opts)
  def heading(%__MODULE__{} = scope, name), do: heading(scope, name, [])
  def heading(name, opts) when is_list(opts), do: heading(nil, name, opts)

  def heading(scope, name, opts) do
    %{locate(scope, :heading, name) | level: Keyword.get(opts, :level)}
  end

  defp locate(nil, role, name), do: %__MODULE__{role: role, name: name}

  defp locate(%__MODULE__{} = scope, role, name),
    do: %__MODULE__{role: role, name: name, scope: scope.scope ++ [scope]}

  ## Queries

  @doc "Each element that the locator finds."
  @spec all(source, t) :: [LazyHTML.t()]
  def all(source, %__MODULE__{} = locator) do
    root = document(source)
    Enum.reduce(locator.scope ++ [locator], [root], &find_in(&2, &1, root))
  end

  @doc "Whether the locator finds any element."
  @spec has?(source, t) :: boolean
  def has?(source, locator), do: all(source, locator) != []

  @doc "The one element that the locator finds. Raises on none or more."
  @spec one(source, t) :: LazyHTML.t()
  def one(source, locator) do
    case all(source, locator) do
      [node] -> node
      nodes -> raise ArgumentError, "#{describe(locator)} found #{length(nodes)} elements"
    end
  end

  @doc "The words of the one element, with spaces folded and icons left out."
  @spec text(source, t) :: String.t()
  def text(source, locator), do: source |> one(locator) |> visible_text()

  @doc "Where the one link that the locator finds leads."
  @spec href(source, t) :: String.t() | nil
  def href(source, locator) do
    source |> one(locator) |> LazyHTML.attribute("href") |> List.first()
  end

  @doc """
  An attribute of the one element that the locator finds, or `nil`: what a
  person cannot read but the browser uses, such as the `action` of a form,
  `aria-current` or `max`.
  """
  @spec attribute(source, t, String.t()) :: String.t() | nil
  def attribute(source, locator, name), do: source |> one(locator) |> attribute(name)

  @doc "Where the one image that the locator finds comes from."
  @spec src(source, t) :: String.t() | nil
  def src(source, locator) do
    source |> one(locator) |> LazyHTML.attribute("src") |> List.first()
  end

  @doc """
  What the one field that the locator finds holds: the `value` of an input,
  the words of a text area, or the words of the chosen option of a select
  (the first option when none is chosen, as in a browser).
  """
  @spec value(source, t) :: String.t() | nil
  def value(source, locator) do
    node = one(source, locator)

    case LazyHTML.tag(node) do
      ["select"] ->
        chosen = LazyHTML.query(node, "option[selected]")
        options = if Enum.empty?(chosen), do: LazyHTML.query(node, "option"), else: chosen
        options |> Enum.take(1) |> Enum.map_join(&visible_text/1)

      ["textarea"] ->
        LazyHTML.text(node)

      _input ->
        attribute(node, "value")
    end
  end

  @doc "Whether the one checkbox or radio button that the locator finds is checked."
  @spec checked?(source, t) :: boolean
  def checked?(source, locator), do: source |> one(locator) |> LazyHTML.attribute("checked") != []

  @doc "Whether the one disclosure (`details`) that the locator finds is open."
  @spec open?(source, t) :: boolean
  def open?(source, locator), do: source |> one(locator) |> LazyHTML.attribute("open") != []

  @doc "The accessible names of each element, in the order of the page."
  @spec names(source, t) :: [String.t()]
  def names(source, %__MODULE__{} = locator) do
    root = document(source)
    Enum.map(all(root, locator), &accessible_name(&1, locator.role, root))
  end

  ## Phoenix.LiveViewTest

  @doc """
  The `Phoenix.LiveViewTest.Element` of the one element that the locator
  finds, for `render_click/1` and the like.
  """
  def locate(view, %__MODULE__{} = locator) do
    root = document(view)
    {selector, text} = selector(one(root, locator), locator, root)
    Phoenix.LiveViewTest.element(view, selector, text)
  end

  @doc """
  Presses the one button or link that the locator finds.

  With a `PhoenixTest` session it clicks as `click_button/3` or
  `click_link/3` do, and returns the session. With a
  `Phoenix.LiveViewTest` view it is `render_click/1`.
  """
  def click(%Phoenix.LiveViewTest.View{} = view, %__MODULE__{} = locator),
    do: view |> locate(locator) |> Phoenix.LiveViewTest.render_click()

  def click(%PhoenixTest.Playwright{} = session, %__MODULE__{} = locator),
    do: PhoenixTest.Playwright.click(session, playwright(locator))

  # `click/2` of `PhoenixTest.Playwright`, which `use RescordWeb.Roles,
  # browser: true` leaves out.
  def click(%PhoenixTest.Playwright{} = session, selector) when is_binary(selector),
    do: PhoenixTest.Playwright.click(session, selector)

  def click(session, %__MODULE__{role: role} = locator) when role in [:button, :link] do
    root = document(session)
    node = one(root, locator)
    words = visible_text(node)

    css =
      case selector(node, locator, root) do
        {css, nil} -> css
        {_css, _words} -> narrow(node, words, root)
      end

    case role do
      :button -> PhoenixTest.click_button(session, css, words)
      :link -> PhoenixTest.click_link(session, css, words)
    end
  end

  ## PhoenixTest

  @doc """
  Brings in `PhoenixTest` with `within/3`, `assert_has/2,3` and
  `refute_has/2,3` of this module, which take a locator or a CSS selector.
  """
  defmacro __using__(opts) do
    browser =
      if Keyword.get(opts, :browser, false) do
        quote do
          # What `PhoenixTest.Playwright.Case` imports (0.19.0), but `click/2`,
          # which takes a locator here.
          import PhoenixTest.Playwright,
            only: [
              add_cookies: 2,
              add_session_cookie: 3,
              assert_screenshot: 2,
              assert_screenshot: 3,
              clear_cookies: 1,
              clear_cookies: 2,
              click: 3,
              click: 4,
              click_button: 4,
              click_link: 4,
              drag: 3,
              evaluate: 2,
              evaluate: 3,
              evaluate: 4,
              press: 3,
              press: 4,
              screenshot: 2,
              screenshot: 3,
              step: 3,
              type: 3,
              type: 4,
              visit: 3,
              with_dialog: 3
            ]
        end
      end

    quote do
      import PhoenixTest,
        except: [within: 3, assert_has: 2, assert_has: 3, refute_has: 2, refute_has: 3]

      unquote(browser)
      import RescordWeb.Roles
    end
  end

  @doc "Runs `fun` inside the one element that the locator finds."
  def within(session, %__MODULE__{} = locator, fun) when is_function(fun, 1),
    do: PhoenixTest.within(session, scope_selector(session, locator), fun)

  def within(session, selector, fun), do: PhoenixTest.within(session, selector, fun)

  @doc """
  Asserts that the locator finds an element. Options: `text:` (words that
  the element holds), `count:`, and `state:`, the kind of a state that the
  element holds (`data-state`, ADR 0004), whose words `text:` then gives:
  `assert_has(item_row("Meadow hay"), state: "alert", text: "Order more")`.
  """
  def assert_has(session, locator, opts \\ [])

  def assert_has(%PhoenixTest.Playwright{} = session, %__MODULE__{} = locator, opts) do
    in_browser(session, locator, opts, &PhoenixTest.assert_has/3)
  end

  def assert_has(session, %__MODULE__{} = locator, opts) do
    found = matches(session, locator, opts)

    unless found?(found, opts) do
      raise ExUnit.AssertionError,
        message: "#{describe(locator)} #{inspect(opts)} found #{length(found)} elements"
    end

    session
  end

  def assert_has(session, selector, opts), do: PhoenixTest.assert_has(session, selector, opts)

  @doc "Asserts that the locator finds no element (with `text:`, none that holds it)."
  def refute_has(session, locator, opts \\ [])

  def refute_has(%PhoenixTest.Playwright{} = session, %__MODULE__{} = locator, opts) do
    in_browser(session, locator, opts, &PhoenixTest.refute_has/3)
  end

  def refute_has(session, %__MODULE__{} = locator, opts) do
    case matches(session, locator, opts) do
      [] ->
        session

      found ->
        raise ExUnit.AssertionError,
          message: "#{describe(locator)} #{inspect(opts)} found #{length(found)} elements"
    end
  end

  def refute_has(session, selector, opts), do: PhoenixTest.refute_has(session, selector, opts)

  # `assert_has/3` of PhoenixTest.Playwright puts its selector in `css=`, so
  # a selector by role goes in `within/3`, and the assertion is on `:scope`.
  defp in_browser(session, locator, opts, assertion) do
    {selector, opts} =
      case Keyword.pop(opts, :state) do
        {nil, opts} -> {":scope", opts}
        {kind, opts} -> {"[data-state=#{kind}]", opts}
      end

    PhoenixTest.within(session, playwright(locator), &assertion.(&1, selector, opts))
  rescue
    error in ExUnit.AssertionError ->
      reraise ExUnit.AssertionError,
              [message: "#{describe(locator)} #{inspect(opts)}: #{error.message}"],
              __STACKTRACE__
  end

  defp matches(session, locator, opts) do
    found = all(document(session), locator)

    case Keyword.fetch(opts, :state) do
      {:ok, kind} ->
        Enum.filter(found, fn node ->
          node
          |> LazyHTML.query("[data-state=#{kind}]")
          |> Enum.any?(&holds?(&1, opts[:text]))
        end)

      :error ->
        Enum.filter(found, &holds?(&1, opts[:text]))
    end
  end

  defp holds?(_node, nil), do: true
  defp holds?(node, %Regex{} = text), do: visible_text(node) =~ text
  defp holds?(node, text), do: String.contains?(visible_text(node), text)

  defp found?(found, opts) do
    case Keyword.fetch(opts, :count) do
      {:ok, count} -> length(found) == count
      :error -> found != []
    end
  end

  defp scope_selector(%PhoenixTest.Playwright{}, locator), do: playwright(locator)

  defp scope_selector(session, locator) do
    root = document(session)

    case selector(
           one(root, locator),
           %{locator | scope: []} |> Map.put(:scope, locator.scope),
           root
         ) do
      {css, nil} ->
        css

      {css, _text} ->
        raise ArgumentError, "#{describe(locator)} has no selector of its own (#{css})"
    end
  end

  ## Playwright

  @doc false
  # The locator as a selector of Playwright, which finds by role and name
  # itself: `internal:role=region[name="Lots"s] >> internal:role=button[...]`.
  def playwright(%__MODULE__{} = locator) do
    Enum.map_join(locator.scope ++ [locator], " >> ", &playwright_one/1)
  end

  defp playwright_one(%{role: :field, name: name}), do: "internal:label=#{pw_name(name)}"

  # Playwright gives neither a name from its words, so these are XPath.
  defp playwright_one(%{role: :details, name: name}),
    do:
      "xpath=.//details[summary[@aria-label=#{xpath_text(name)} or normalize-space()=#{xpath_text(name)}]]"

  defp playwright_one(%{role: :definition, name: name}),
    do: "xpath=.//dd[preceding-sibling::dt[1][normalize-space()=#{xpath_text(name)}]]"

  defp playwright_one(%{role: :item, name: nil}), do: "internal:role=listitem"

  defp playwright_one(%{role: :item, name: name}),
    do: "internal:role=listitem >> internal:has-text=#{pw_text(name)} >> nth=0"

  defp playwright_one(%{role: role, name: name, level: level}) do
    attributes =
      [name && "[name=#{pw_name(name)}]", level && "[level=#{level}]"]
      |> Enum.reject(&is_nil/1)
      |> Enum.join()

    "internal:role=#{pw_role(role)}#{attributes}"
  end

  defp pw_role(:image), do: "img"
  defp pw_role(role), do: Atom.to_string(role)

  defp pw_name(%Regex{source: source}), do: "/#{source}/"

  defp pw_name(name), do: JSON.encode!(name) <> "s"

  defp xpath_text(%Regex{} = name),
    do: raise(ArgumentError, "a browser test finds #{inspect(name)} by its exact words")

  defp xpath_text(text) do
    if String.contains?(text, ~s(")), do: "'#{text}'", else: ~s("#{text}")
  end

  defp pw_text(%Regex{source: source}), do: "/#{source}/"
  defp pw_text(text), do: JSON.encode!(text)

  ## Finding

  defp document(%Phoenix.LiveViewTest.View{} = view),
    do: view |> Phoenix.LiveViewTest.render() |> LazyHTML.from_fragment()

  defp document(%LazyHTML{} = html), do: html

  # PhoenixTest's session of a LiveView or a controller. `render_html/1` is
  # in its driver protocol, which has no docs: pinned with `~> 0.14.0`.
  defp document(%{__struct__: struct} = session)
       when struct in [PhoenixTest.Live, PhoenixTest.Static],
       do: PhoenixTest.Driver.render_html(session)

  defp document(html) when is_binary(html) do
    if html =~ ~r/^\s*<!doctype/i,
      do: LazyHTML.from_document(html),
      else: LazyHTML.from_fragment(html)
  end

  defp find_in(scopes, %__MODULE__{} = locator, root) do
    Enum.flat_map(scopes, fn scope ->
      scope
      |> inside(root)
      |> candidates(locator)
      |> Enum.filter(&level?(&1, locator.level))
      |> Enum.filter(&named?(&1, locator, root))
    end)
  end

  # What is `hidden`, or inside it, is not on the page, as in a browser.
  @shown ":not([hidden], [hidden] *, [aria-hidden=true], [aria-hidden=true] *)"

  # `LazyHTML.query/2` finds the node itself too, and the top nodes of a
  # fragment. The page is searched whole; a part of it only inside, so that
  # a region in a region is not the region itself.
  defp inside(root, root), do: root
  defp inside(scope, _root), do: LazyHTML.child_nodes(scope)

  defp candidates(scope, %{role: role}) do
    selector =
      @css[role]
      |> String.split(~r/,(?![^(]*\))/)
      |> Enum.map_join(", ", &(String.trim(&1) <> @shown))

    scope |> LazyHTML.query(selector) |> Enum.to_list()
  end

  defp level?(_node, nil), do: true
  defp level?(node, level), do: LazyHTML.tag(node) == ["h#{level}"]

  defp named?(_node, %{name: nil, role: role}, _root) when role != :region, do: true

  defp named?(node, %{name: nil, role: :region}, root),
    do: accessible_name(node, :region, root) != ""

  defp named?(node, %{name: %Regex{} = name, role: role}, root),
    do: accessible_name(node, role, root) =~ name

  defp named?(node, %{name: name, role: role}, root),
    do: accessible_name(node, role, root) == name

  ## Names

  @doc false
  def accessible_name(node, role, root) do
    cond do
      (ids = attribute(node, "aria-labelledby")) != nil ->
        ids
        |> String.split()
        |> Enum.map_join(" ", &(root |> LazyHTML.query_by_id(&1) |> visible_text()))
        |> fold()

      (label = attribute(node, "aria-label")) != nil ->
        fold(label)

      role == :field ->
        field_label(node, root)

      role == :image ->
        fold(attribute(node, "alt") || "")

      # The name of its summary: an `aria-label`, as a confirm step has, or its words.
      role == :details ->
        summary = node |> LazyHTML.child_nodes() |> LazyHTML.filter("summary")
        fold(attribute(summary, "aria-label") || visible_text(summary))

      role == :definition ->
        node
        |> LazyHTML.parent_node()
        |> LazyHTML.child_nodes()
        |> LazyHTML.filter("dt")
        |> visible_text()

      role == :figure ->
        node |> LazyHTML.query("figcaption") |> visible_text()

      role == :table ->
        node |> LazyHTML.query("caption") |> visible_text()

      role in @named_by_content ->
        visible_text(node) |> fallback(attribute(node, "value") || attribute(node, "title"))

      true ->
        ""
    end
  end

  defp fallback("", other), do: fold(other || "")
  defp fallback(text, _other), do: text

  defp field_label(node, root) do
    id = attribute(node, "id")

    by_for = if id, do: root |> LazyHTML.query(~s(label[for="#{id}"])) |> visible_text(), else: ""

    if by_for != "" do
      by_for
    else
      html = LazyHTML.to_html(node)

      root
      |> LazyHTML.query("label")
      |> Enum.find(fn label ->
        label
        |> LazyHTML.query("input, select, textarea")
        |> Enum.any?(&(LazyHTML.to_html(&1) == html))
      end)
      |> case do
        nil -> ""
        label -> visible_text(label)
      end
    end
  end

  @doc false
  def visible_text(%LazyHTML{} = node) do
    node |> LazyHTML.to_tree() |> tree_text() |> fold()
  end

  defp tree_text(nodes) when is_list(nodes), do: Enum.map_join(nodes, " ", &tree_text/1)
  defp tree_text(text) when is_binary(text), do: text
  defp tree_text({:comment, _}), do: ""

  defp tree_text({_tag, attributes, children}) do
    if {"aria-hidden", "true"} in attributes or List.keymember?(attributes, "hidden", 0),
      do: "",
      else: tree_text(children)
  end

  defp fold(text), do: text |> String.split() |> Enum.join(" ")

  defp attribute(node, name), do: node |> LazyHTML.attribute(name) |> List.first()

  ## Selectors for Phoenix.LiveViewTest

  # A CSS selector and text filter that find this one node. An id is best; a
  # name in an attribute is next; else the tag, inside its scope, and the
  # element's own words. LiveViewTest raises if that is not one element.
  defp selector(node, locator, root) do
    tag = node |> LazyHTML.tag() |> List.first()

    cond do
      id = attribute(node, "id") ->
        {"##{css_escape(id)}", nil}

      label = attribute(node, "aria-label") ->
        {scope_css(locator, root) <> ~s(#{tag}[aria-label="#{quote_css(label)}"]), nil}

      ids = attribute(node, "aria-labelledby") ->
        {scope_css(locator, root) <> ~s(#{tag}[aria-labelledby="#{quote_css(ids)}"]), nil}

      name = attribute(node, "name") ->
        {scope_css(locator, root) <> ~s(#{tag}[name="#{quote_css(name)}"]), nil}

      # A row of Cinder has no id, but its title has one (ADR 0097).
      inner = node |> LazyHTML.query("[id]") |> Enum.find(&(&1 |> LazyHTML.tag() != [tag])) ->
        {"#{tag}:has(##{css_escape(attribute(inner, "id"))})", nil}

      true ->
        words = node |> visible_text() |> String.split() |> Enum.map_join("\\s+", &Regex.escape/1)
        {scope_css(locator, root) <> tag, Regex.compile!("^\\s*#{words}\\s*$")}
    end
  end

  # PhoenixTest finds a button or a link by a part of its words, so "Save"
  # finds "Save the token" too. For an element with no selector of its own,
  # this is the tag inside the nearest element with an id that holds no
  # other of those words, below the part of the page that `within/3` gives.
  defp narrow(node, words, root) do
    tag = node |> LazyHTML.tag() |> List.first()
    tops = root |> Enum.map(&LazyHTML.to_html/1) |> MapSet.new()

    node
    |> LazyHTML.parent_node()
    |> Stream.unfold(fn ancestor ->
      if Enum.empty?(ancestor) or MapSet.member?(tops, LazyHTML.to_html(ancestor)),
        do: nil,
        else: {ancestor, LazyHTML.parent_node(ancestor)}
    end)
    |> Enum.find_value(tag, fn ancestor ->
      id = attribute(ancestor, "id")

      holders =
        ancestor |> LazyHTML.query(tag) |> Enum.count(&String.contains?(visible_text(&1), words))

      if id && holders == 1, do: "##{css_escape(id)} #{tag}"
    end)
  end

  defp quote_css(value), do: String.replace(value, ~S("), ~S(\"))

  defp scope_css(%{scope: []}, _root), do: ""

  defp scope_css(%{scope: scope}, root) do
    scope
    |> Enum.with_index(1)
    |> Enum.map_join(" ", fn {_locator, n} ->
      chain = Enum.take(scope, n)
      inner = List.last(chain)
      node = one(root, %{inner | scope: Enum.drop(chain, -1)})

      case selector(node, %{inner | scope: []}, root) do
        {css, nil} ->
          css

        {css, _text} ->
          raise ArgumentError, "#{describe(inner)} has no selector of its own (#{css})"
      end
    end)
    |> Kernel.<>(" ")
  end

  defp css_escape(id), do: String.replace(id, ~r/([^\w-])/, "\\\\\\1")

  defp describe(%__MODULE__{} = locator) do
    (locator.scope ++ [locator])
    |> Enum.map_join(" > ", fn l ->
      name = if l.name, do: "(#{inspect(l.name)})", else: ""
      level = if l.level, do: "[level #{l.level}]", else: ""
      "#{l.role}#{name}#{level}"
    end)
  end
end
