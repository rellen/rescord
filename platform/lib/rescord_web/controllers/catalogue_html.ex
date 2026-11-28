defmodule RescordWeb.CatalogueHTML do
  @moduledoc """
  The catalogue of the components, for a developer (ADR 00XX): each
  element that the stylesheet styles and each core component, by itself
  and in each of its states. The router has the page in development and
  in the tests alone. The page shows no record and reads no database.

  ## An example

  An example is a template of its own in `catalogue_html/examples/`, and a
  line of `@examples` with its group and its title. The name of the file
  is the title in small letters with `_` between the words: the example
  "A field with an error" is `a_field_with_an_error.html.heex`. The
  catalogue renders the template and shows its text below it, so the
  markup is written one time. A template may read the assigns of the
  page, such as `@points`.

  ## The rules of an example

  `PhoneTest` and `AccessibilityTest` visit the catalogue, so an example
  is held to the rules of a page (ADR 0061, ADR 0090):

    * its headings start at `h4`, because its title is an `h3`;
    * each `id` starts with `example-` and is its own;
    * a `nav` has a name of its own.

  A new core component, or a new state of one, gets an example here.
  `RescordWeb.CatalogueControllerTest` holds that for `CoreComponents`
  and for each icon.
  """
  use RescordWeb, :html

  import RescordWeb.ChartComponents

  embed_templates "catalogue_html/*"
  embed_templates "catalogue_html/examples/*"

  # The examples, in the order of the page: the group, and the title.
  @examples [
    # The stylesheet is classless (ADR 0004), so the look of Rescord is
    # the look of the elements.
    {"Elements", "Text"},
    {"Elements", "Lists"},
    {"Elements", "A card"},
    {"Elements", "A list of things with a button each"},
    {"Elements", "A table by hand"},
    {"Elements", "A part that opens"},
    {"Elements", "A group of choices"},
    {"Core components", "Buttons"},
    {"Core components", "A button with an icon alone"},
    {"Core components", "A field"},
    {"Core components", "A field with a hint"},
    {"Core components", "A field with an error"},
    {"Core components", "A date, a choice and a text of lines"},
    {"Core components", "A box to tick"},
    {"Core components", "A list of facts"},
    {"Core components", "A table"},
    {"Core components", "States"},
    {"Core components", "What an action refused"},
    {"Core components", "Notices"},
    {"Core components", "Icons"},
    # ADR 0080.
    {"Charts", "A line chart"},
    {"Charts", "A sparkline beside its value"}
  ]

  @directory Path.join(__DIR__, "catalogue_html/examples")

  # `embed_templates` compiles this module again when a template changes,
  # so the text that the page shows is the text that it compiled.
  @listed (for {group, title} <- @examples do
             name = title |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_")
             name = String.trim(name, "_")

             %{
               id: "example-" <> String.replace(name, "_", "-"),
               group: group,
               title: title,
               function: String.to_atom(name),
               source: File.read!(Path.join(@directory, name <> ".html.heex"))
             }
           end)

  @type example :: %{
          id: String.t(),
          group: String.t(),
          title: String.t(),
          function: atom,
          source: String.t()
        }

  @doc "Each example, in the order of the page."
  @spec examples() :: [example]
  def examples, do: @listed

  @doc "The examples by group, in the order of the page."
  @spec groups() :: [{String.t(), [example]}]
  def groups do
    examples()
    |> Enum.chunk_by(& &1.group)
    |> Enum.map(fn [first | _] = examples -> {first.group, examples} end)
  end

  @doc "The `id` of the heading of a group."
  @spec anchor(String.t()) :: String.t()
  def anchor(group), do: "group-" <> (group |> String.downcase() |> String.replace(" ", "-"))

  @doc "Renders one example with the assigns of the page."
  def render_example(%{function: function}, assigns), do: apply(__MODULE__, function, [assigns])
end
