defmodule Rescord.Reports.Wording do
  @moduledoc """
  The words of a report (ADR 0076).

  A report reads its facts in the core: records, dates and the values of the
  fixed lists. The words for those are in the web layer, which words the
  pages too (`RescordWeb.ResidentWords` and the others), and the core does
  not call the web layer. So the configuration names the module that words
  the reports, as it names the sources of the grants:

      config :rescord, :report_wording, RescordWeb.ReportWords

  That module turns the facts of a report into the data of its template:
  maps, lists, numbers and text that is ready to show. The template only
  lays that data out.
  """

  @typedoc "The data of a template: maps, lists, text, numbers, booleans and `nil`."
  @type data :: %{optional(atom) => term}

  @doc """
  The data of the template of `report`, from the facts that
  `Rescord.Reports.Facts` read. The facts also hold `:organisation` and
  `:made_at`, the instant of the request.
  """
  @callback data(report :: atom, facts :: map) :: data

  # A module name is an atom, so this is no use of the web layer when this
  # module compiles.
  @module Application.compile_env(:rescord, :report_wording)

  @doc "The module of the configuration that words the reports."
  @spec module() :: module
  def module, do: @module
end
