defmodule Rescord.Reports.Facts.Places do
  @moduledoc """
  The places of an organisation for a report: the path of each location,
  from the outermost one, and where each resident lives.
  """

  alias Rescord.Locations

  @typedoc "The names of a location and of each location around it, the outermost first."
  @type path :: [String.t()]

  @doc """
  Reads the housing. Returns `{:ok, places}`, with:

    * `tree` - the tree of `Rescord.Locations.tree/1`;
    * `paths` - the path of each location, by its id;
    * `homes` - the paths of the locations where each resident lives, by
      the id of the resident: its own placement, or the placement of each
      group that it lives with.
  """
  @spec read(keyword) :: {:ok, %{tree: [map], paths: map, homes: map}} | {:error, term}
  def read(options) do
    with {:ok, tree} <- Locations.tree(options) do
      rows = walk(tree, [])

      paths = Map.new(rows, fn {node, path} -> {node.location.id, path} end)

      homes =
        for {node, path} <- rows, id <- resident_ids(node), reduce: %{} do
          homes -> Map.update(homes, id, [path], &(&1 ++ [path]))
        end

      {:ok, %{tree: tree, paths: paths, homes: homes}}
    end
  end

  # Each node with its path, a location before the locations inside it.
  defp walk(nodes, above) do
    Enum.flat_map(nodes, fn node ->
      path = above ++ [node.location.name]
      [{node, path} | walk(node.children, path)]
    end)
  end

  defp resident_ids(node) do
    Enum.map(node.residents, & &1.resident_id) ++
      for {_placement, _group, members} <- node.groups, member <- members, do: member.resident_id
  end
end
