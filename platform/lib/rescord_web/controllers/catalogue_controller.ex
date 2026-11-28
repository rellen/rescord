defmodule RescordWeb.CatalogueController do
  @moduledoc """
  Shows the catalogue of the components (ADR 00XX), for a developer who
  writes or changes one. The router has the page with the setting
  `catalogue`, which development and the tests turn on: the release has no
  such page.
  """

  use RescordWeb, :controller

  def index(conn, _params) do
    render(conn, :index,
      page_title: "Components",
      groups: RescordWeb.CatalogueHTML.groups(),
      points: points()
    )
  end

  # The series of the chart examples: five weights of a rabbit that does
  # not exist.
  defp points do
    for {day, grams} <- [
          {~D[2026-10-03], 2180},
          {~D[2026-10-17], 2215},
          {~D[2026-10-31], 2260},
          {~D[2026-11-14], 2305},
          {~D[2026-11-28], 2340}
        ] do
      %{
        id: "example-point-#{day}",
        at: DateTime.new!(day, ~T[09:00:00], "Etc/UTC"),
        value: Decimal.new(grams),
        label: "#{Calendar.strftime(day, "%-d %B %Y")}: #{grams} g"
      }
    end
  end
end
