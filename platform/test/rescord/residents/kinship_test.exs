defmodule Rescord.Residents.KinshipTest do
  @moduledoc """
  Holds the words that Rescord gives a group from its parent links and its
  families (`docs/domain.md`, section 5.4). The module reads no database, so
  each test gives it plain data.
  """

  use ExUnit.Case, async: true

  alias Rescord.Residents.Kinship

  defp female(id), do: %{id: id, sex: :female}
  defp male(id), do: %{id: id, sex: :male}
  defp unknown(id), do: %{id: id, sex: :unknown}

  defp mother(child, parent), do: %{child_id: child, parent_id: parent, role: :mother}
  defp father(child, parent), do: %{child_id: child, parent_id: parent, role: :father}

  describe "a parent and its young in one group" do
    test "are a mother and a daughter" do
      assert Kinship.describe([female(:toffee), female(:caramel)], [mother(:caramel, :toffee)]) ==
               "Mother and daughter"
    end

    test "are a mother, a father and their young, with a number for more than one" do
      members = [female(:maple), male(:rolo), female(:fern), female(:sage)]

      links = [
        mother(:fern, :maple),
        father(:fern, :rolo),
        mother(:sage, :maple),
        father(:sage, :rolo)
      ]

      assert Kinship.describe(members, links) == "Mother, father and two daughters"
    end

    test "name a son, a daughter, and young of a sex that is not known" do
      members = [male(:rolo), male(:ash), female(:fern), unknown(:pip), unknown(:dot)]
      links = for child <- [:ash, :fern, :pip, :dot], do: father(child, :rolo)

      assert Kinship.describe(members, links) == "Father, daughter, son and two young"
    end

    test "name a member that is related to nobody there as unrelated, with its sex" do
      members = [female(:toffee), female(:caramel), male(:basil)]

      assert Kinship.describe(members, [mother(:caramel, :toffee)]) ==
               "Mother, daughter and an unrelated male"
    end
  end

  describe "siblings in one group" do
    # Each of these has its mother outside the group.
    defp litter(children), do: Enum.map(children, &mother(&1, :outside))

    test "are sisters, brothers, or a brother and a sister" do
      assert Kinship.describe([female(:a), female(:b)], litter([:a, :b])) == "Sisters"
      assert Kinship.describe([male(:a), male(:b)], litter([:a, :b])) == "Brothers"
      assert Kinship.describe([male(:a), female(:b)], litter([:a, :b])) == "Brother and sister"
    end

    test "have a number when they are more than two" do
      three = [female(:a), female(:b), female(:c)]
      assert Kinship.describe(three, litter([:a, :b, :c])) == "Three sisters"

      mixed = [female(:a), female(:b), male(:c)]
      assert Kinship.describe(mixed, litter([:a, :b, :c])) == "Two sisters and a brother"
    end

    test "come with a member that is unrelated" do
      members = [female(:clover), female(:juniper), male(:basil)]

      assert Kinship.describe(members, litter([:clover, :juniper])) ==
               "Sisters and an unrelated male"

      four = [female(:a), female(:b), female(:c), male(:d)]

      assert Kinship.describe(four, litter([:a, :b, :c])) ==
               "Three sisters and an unrelated male"
    end

    test "need one parent in common, and not two" do
      links = [mother(:a, :m), father(:a, :f), mother(:b, :m), father(:b, :other)]
      assert Kinship.describe([female(:a), female(:b)], links) == "Sisters"
    end

    test "are not siblings with other parents" do
      links = [mother(:a, :m), mother(:b, :n)]
      assert Kinship.describe([female(:a), female(:b)], links) == nil
    end

    test "are the larger set when a group has two sets" do
      members = [female(:a), female(:b), female(:c), male(:x), male(:y)]
      links = litter([:a, :b, :c]) ++ [mother(:x, :other), mother(:y, :other)]

      assert Kinship.describe(members, links) == "Three sisters and two unrelated males"
    end
  end

  describe "a family with no known parent" do
    test "makes its members siblings" do
      families = %{a: [:litter], b: [:litter], c: [:litter]}

      assert Kinship.describe([female(:a), male(:b), male(:c)], [], families) ==
               "A sister and two brothers"
    end

    test "does not make siblings of members of two families" do
      assert Kinship.describe([female(:a), female(:b)], [], %{a: [:one], b: [:two]}) == nil
    end

    test "does not make a sibling of a member that has a parent link" do
      # `b` has a known mother, so the family alone says nothing about it.
      families = %{a: [:litter], b: [:litter]}
      assert Kinship.describe([female(:a), female(:b)], [mother(:b, :m)], families) == nil
    end
  end

  describe "a group with no relation" do
    test "has no words" do
      assert Kinship.describe([female(:a), male(:b)], []) == nil
      assert Kinship.describe([female(:a)], []) == nil
      assert Kinship.describe([], []) == nil
    end
  end

  test "a number above ten is in digits" do
    members = for id <- 1..12, do: female(id)
    links = for id <- 1..12, do: mother(id, :outside)

    assert Kinship.describe(members, links) == "12 sisters"
  end
end
