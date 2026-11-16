defmodule Rescord.Residents.Kinship do
  @moduledoc """
  Says in words how the members of a group are related, for example
  `Sisters and an unrelated male` (`docs/domain.md`, section 5.4).

  The words come from two facts that Rescord stores, and it stores no
  relation other than those (design rule 6):

    * a parent link: one resident is the mother or the father of another;
    * a family: a named set of residents, for example a litter that came
      with no known parent.

  ## The rules

  Two residents are siblings when they have a parent in common. Two residents
  of one family are siblings too, when neither has a parent link: that is the
  litter with no known parent.

  1. When a member is a parent of another member, the words name each parent
     and then the young: `Mother, father and two daughters`.
  2. In each other case the words name the largest set of siblings:
     `Sisters`, `Three brothers`, `Brother and sister`.
  3. Each member that is in neither is `unrelated`, with its sex.
  4. When no member is related to another, there are no words: the function
     returns `nil`.

  This module is plain Elixir. It reads no database.
  """

  @typedoc "A member of the group: its id and its sex."
  @type member :: %{id: term, sex: :female | :male | :unknown}

  @typedoc "A parent link: `parent_id` is the `role` of `child_id`."
  @type link :: %{child_id: term, parent_id: term, role: :mother | :father}

  @numbers ~w(no one two three four five six seven eight nine ten)

  @doc """
  The words for a group. `links` are the parent links of the members, and
  `families` gives the ids of the families of each member that has one.
  """
  @spec describe([member], [link], %{optional(term) => [term]}) :: String.t() | nil
  def describe(members, links, families \\ %{}) do
    ids = MapSet.new(members, & &1.id)
    inside = Enum.filter(links, &(&1.child_id in ids and &1.parent_id in ids))

    words =
      if inside == [],
        do: siblings(members, links, families),
        else: parents_and_young(members, inside)

    case words do
      nil -> nil
      {related, others} -> sentence(related ++ unrelated(others))
    end
  end

  # Rule 1: the parents that are members, then their young.
  defp parents_and_young(members, inside) do
    parent_ids = MapSet.new(inside, & &1.parent_id)
    child_ids = MapSet.new(inside, & &1.child_id)

    # A member that is a parent and also a child of a member is named as a parent.
    parents = Enum.filter(members, &(&1.id in parent_ids))
    young = Enum.filter(members, &(&1.id in child_ids and &1.id not in parent_ids))
    others = Enum.reject(members, &(&1.id in parent_ids or &1.id in child_ids))

    roles = for parent <- parents, do: role_of(parent, inside)

    related =
      count_each(roles, mother: {"mother", "mothers"}, father: {"father", "fathers"}) ++
        count_each(Enum.map(young, & &1.sex),
          female: {"daughter", "daughters"},
          male: {"son", "sons"},
          unknown: {"young", "young"}
        )

    {related, others}
  end

  defp role_of(parent, inside) do
    Enum.find_value(inside, &if(&1.parent_id == parent.id, do: &1.role))
  end

  # Rule 2: the largest set of siblings among the members.
  defp siblings(members, links, families) do
    case largest_set(members, links, families) do
      nil ->
        nil

      set ->
        others = Enum.reject(members, &(&1 in set))

        related =
          case Enum.frequencies_by(set, & &1.sex) do
            %{female: 1, male: 1} = sexes when map_size(sexes) == 2 ->
              ["brother", "sister"]

            # A pair needs no number: `Sisters`, and not `Two sisters`.
            %{female: 2} = sexes when map_size(sexes) == 1 ->
              ["sisters"]

            %{male: 2} = sexes when map_size(sexes) == 1 ->
              ["brothers"]

            %{unknown: 2} = sexes when map_size(sexes) == 1 ->
              ["siblings"]

            # In a larger set, one of a sex takes `a`: `Two sisters and a brother`.
            _other ->
              count_each(Enum.map(set, & &1.sex),
                female: {"a sister", "sisters"},
                male: {"a brother", "brothers"},
                unknown: {"a sibling", "siblings"}
              )
          end

        {related, others}
    end
  end

  # The sets of siblings are the parts of the group that the relation joins.
  defp largest_set(members, links, families) do
    parents = Enum.group_by(links, & &1.child_id, & &1.parent_id)

    members
    |> Enum.reduce([], fn member, sets ->
      {joined, apart} =
        Enum.split_with(sets, fn set ->
          Enum.any?(set, &sibling?(&1, member, parents, families))
        end)

      [[member | List.flatten(joined)] | apart]
    end)
    |> Enum.filter(&(length(&1) > 1))
    |> Enum.max_by(&length/1, fn -> nil end)
  end

  defp sibling?(one, other, parents, families) do
    of_one = Map.get(parents, one.id, [])
    of_other = Map.get(parents, other.id, [])

    cond do
      of_one != [] and of_other != [] -> Enum.any?(of_one, &(&1 in of_other))
      of_one == [] and of_other == [] -> same_family?(one, other, families)
      true -> false
    end
  end

  defp same_family?(one, other, families) do
    Enum.any?(Map.get(families, one.id, []), &(&1 in Map.get(families, other.id, [])))
  end

  # Rule 3.
  defp unrelated(others) do
    others
    |> Enum.map(& &1.sex)
    |> count_each(
      female: {"unrelated female", "unrelated females"},
      male: {"unrelated male", "unrelated males"},
      unknown: {"unrelated resident", "unrelated residents"}
    )
    |> Enum.map(fn
      "unrelated " <> _rest = one -> "an " <> one
      many -> many
    end)
  end

  # One word for one, and a number with the plural for more: in the order of
  # `words`, and nothing for a key that is not in `keys`.
  defp count_each(keys, words) do
    counts = Enum.frequencies(keys)

    for {key, {one, many}} <- words, count = Map.get(counts, key, 0), count > 0 do
      if count == 1, do: one, else: "#{number(count)} #{many}"
    end
  end

  defp number(count) when count <= 10, do: Enum.at(@numbers, count)
  defp number(count), do: Integer.to_string(count)

  defp sentence(parts) do
    text =
      case parts do
        [one] -> one
        _more -> Enum.join(Enum.drop(parts, -1), ", ") <> " and " <> List.last(parts)
      end

    {first, rest} = String.split_at(text, 1)
    String.upcase(first) <> rest
  end
end
