defmodule RescordWeb.RoleWords do
  @moduledoc """
  The words of the powers of a role (ADR 0040): an area of work for each
  group of powers, and a sentence for each power. The roles page draws a
  box for each power, in the fieldset of its area.

  A test holds each power of `Rescord.Accounts.Grants.power_keys/0` in one
  area here, with a sentence.
  """

  @areas [
    {"People and settings", [:members, :roles, :settings]},
    {"Lists of values", [:lists]},
    {"Residents", [:residents, :remove_residents]},
    {"Housing", [:placements, :locations]},
    {"Journal", [:journal, :correct_journal]},
    {"Tasks", [:tasks, :routines]},
    {"Calendar", [:calendar]},
    {"Inventory", [:stock, :inventory]},
    {"Transfers", [:transfers]},
    {"Export", [:export]}
  ]

  @words %{
    members: "Invite a person, give a member a role, and remove a member",
    roles: "Define the roles, and what each one may do",
    settings: "Change the settings of the organisation",
    lists: "Change the lists of values",
    residents: "Record residents, their stay, their families, their groups and their photos",
    remove_residents: "Remove a resident that was recorded by mistake, and any photo",
    placements: "Place a resident or a group in a location",
    locations: "Add, change and close the locations",
    journal: "Write journal entries, and correct their own",
    correct_journal: "Correct each journal entry",
    tasks: "Plan, take, complete and skip tasks",
    routines: "Start, change, pause and end routines",
    calendar: "Subscribe to a calendar feed, which copies tasks and dates to a calendar app",
    stock: "Record deliveries, uses, moves, discards and counts of stock",
    inventory: "Keep the items, the suppliers and the reorder levels",
    transfers: "Agree partner refuges, send a resident to one, and answer a transfer",
    export: "Export the data of the organisation as files of CSV"
  }

  @doc "The areas of work, each with its powers, in the order of the page."
  @spec areas() :: [{String.t(), [atom]}]
  def areas, do: @areas

  @doc "The sentence of a power."
  @spec power(atom) :: String.t()
  def power(key), do: Map.fetch!(@words, key)

  @doc "The power with the text of a field of a form, or `:error`. It makes no atom."
  @spec power_of(term) :: {:ok, atom} | :error
  def power_of(text) when is_binary(text) do
    case Enum.find(Map.keys(@words), &(Atom.to_string(&1) == text)) do
      nil -> :error
      key -> {:ok, key}
    end
  end

  def power_of(_other), do: :error

  @doc "The powers of a role, as the names of their areas: `Journal, Tasks`."
  @spec summary([atom]) :: String.t()
  def summary([]), do: "Reads only"

  def summary(powers) do
    @areas
    |> Enum.filter(fn {_area, keys} -> Enum.any?(keys, &(&1 in powers)) end)
    |> Enum.map_join(", ", &elem(&1, 0))
  end
end
