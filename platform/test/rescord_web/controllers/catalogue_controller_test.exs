defmodule RescordWeb.CatalogueControllerTest do
  @moduledoc """
  The catalogue of the components (ADR 0095): the page renders each
  example and shows its markup, and each core component has an example.
  `PhoneTest` and `AccessibilityTest` hold the page in a browser.
  """

  use RescordWeb.ConnCase, async: true

  alias RescordWeb.CatalogueHTML

  test "the page renders each example, with its markup below it", %{conn: conn} do
    html = conn |> get("/dev/components") |> html_response(200)
    document = LazyHTML.from_fragment(html)

    examples = CatalogueHTML.examples()
    assert length(examples) > 20

    for example <- examples do
      assert LazyHTML.text(LazyHTML.query(document, "h3##{example.id}")) == example.title

      assert LazyHTML.text(LazyHTML.query(document, "##{example.id}-markup pre code")) ==
               example.source
    end

    assert html =~ "<title"
    assert html =~ "Components · Rescord"

    # The catalogue is classless as each page is (ADR 0004).
    refute html =~ ~r/\sclass=/
  end

  test "the groups keep the order of the list" do
    assert Enum.map(CatalogueHTML.groups(), &elem(&1, 0)) ==
             ["Elements", "Core components", "Charts"]
  end

  test "each template of an example is in the list, so the page shows it" do
    directory = Path.join(File.cwd!(), "lib/rescord_web/controllers/catalogue_html/examples")

    files =
      directory
      |> File.ls!()
      |> Enum.map(&String.replace_suffix(&1, ".html.heex", ""))
      |> Enum.sort()

    listed = CatalogueHTML.examples() |> Enum.map(&Atom.to_string(&1.function)) |> Enum.sort()

    assert files == listed
  end

  test "each core component has an example" do
    sources = Enum.map_join(CatalogueHTML.examples(), "\n", & &1.source)

    # The header of a page is its `h1`, and a page has one: the header of
    # the catalogue itself is the example. A private component shows in
    # the example of the public one that draws it.
    for {name, _component} <- RescordWeb.CoreComponents.__components__(),
        function_exported?(RescordWeb.CoreComponents, name, 1),
        name != :header do
      assert sources =~ "<.#{name}", "the catalogue has no example of <.#{name}>"
    end
  end

  test "each icon is in the catalogue" do
    %{attrs: attrs} = RescordWeb.CoreComponents.__components__()[:icon]
    names = Enum.find(attrs, &(&1.name == :name)).opts[:values]

    icons = Enum.find(CatalogueHTML.examples(), &(&1.title == "Icons")).source

    assert names != []

    for name <- names do
      assert icons =~ ~s(name="#{name}"), "the catalogue does not show the icon #{name}"
    end
  end

  test "an example has no heading above the fourth level, and each id is its own" do
    sources = Enum.map(CatalogueHTML.examples(), & &1.source)

    for source <- sources do
      refute source =~ ~r/<h[1-3][\s>]/
    end

    ids = sources |> Enum.flat_map(&Regex.scan(~r/\sid="([^"]+)"/, &1)) |> Enum.map(&List.last/1)

    assert ids == Enum.uniq(ids)
    assert Enum.all?(ids, &String.starts_with?(&1, "example-"))
  end
end
