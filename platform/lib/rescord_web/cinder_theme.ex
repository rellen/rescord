defmodule RescordWeb.CinderTheme do
  @moduledoc """
  The theme that Cinder renders with (ADR 0014): almost no class.

  A theme of Cinder is a map from a part of its markup to the classes of that
  part, and each built-in theme is a set of Tailwind classes. Rescord has no
  Tailwind (ADR 0004), so this theme sets each such value to the empty
  string. Cinder also writes the name of most parts into a `data-key`
  attribute, and `assets/css/layers/vendor.css` styles the parts by that
  attribute.

  A few parts and states have no `data-key`, and a class from the theme is
  their only mark: the selected row, the current size of a page, the sort
  buttons of a list. `marks/0` names one class for each. The arrow of a
  choice filter is there too, because Cinder leaves the arrow out when its
  class is empty.

  The names of the sort icons stay those of Cinder, because Cinder writes two
  of them into its markup itself. `vendor.css` draws them.

  `config :cinder, default_theme: RescordWeb.CinderTheme` makes this the theme
  of every collection. Do not pass `theme` to `Cinder.collection`.
  """

  @behaviour Cinder.Theme.Behaviour

  @marks %{
    filter_select_arrow_class: "arrow",
    filter_select_placeholder_class: "placeholder",
    page_size_selected_class: "selected",
    selected_row_class: "selected",
    selected_item_class: "selected",
    sort_controls_class: "sort-controls",
    sort_button_active_class: "active",
    button_primary_class: "primary",
    button_danger_class: "danger"
  }

  @doc """
  The classes that the theme does set: the mark of a part or of a state that
  Cinder marks in no other way.
  """
  def marks, do: @marks

  @impl true
  def resolve_theme do
    Cinder.Theme.complete_default()
    |> Map.new(fn {key, value} -> if class?(key), do: {key, ""}, else: {key, value} end)
    |> Map.merge(@marks)
  end

  defp class?(key), do: key |> Atom.to_string() |> String.ends_with?("_class")
end
