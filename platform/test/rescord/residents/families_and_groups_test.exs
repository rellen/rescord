defmodule Rescord.Residents.FamiliesAndGroupsTest do
  @moduledoc """
  Holds the families and the groups of residents (`docs/domain.md`, sections
  5.3 and 5.4): the parent links and their rules, a family, a group with its
  members over time, and the words that Rescord calculates for a group.

  `Rescord.Residents.KinshipTest` holds the words for each shape of a group.
  This test holds that the words come from what the database has.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.Residents

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, member} = member!(organisation, :member, root)
    lists = lists!(organisation, root)
    options = [actor: member, tenant: organisation]

    pig = fn name, sex -> resident!(lists, options, %{name: name, sex: sex}) end

    {:ok,
     root: root,
     organisation: organisation,
     member: member,
     lists: lists,
     options: options,
     maple: pig.("Maple", :female),
     rolo: pig.("Rolo", :male),
     fern: pig.("Fern", :female),
     sage: pig.("Sage", :female),
     basil: pig.("Basil", :male)}
  end

  defp parent!(young, parent, role, options) do
    Residents.record_parent!(%{resident_id: young.id, parent_id: parent.id, role: role}, options)
  end

  defp group!(residents, options, attributes \\ %{}) do
    Residents.form_group!(
      Map.put(attributes, :resident_ids, Enum.map(residents, & &1.id)),
      options
    )
  end

  defp words(group, options) do
    {:ok, group} = Residents.group_with_facts(group.id, options)
    Residents.words(group)
  end

  describe "a parent link" do
    test "gives a resident a mother and a father, one of each", context do
      options = context.options
      parent!(context.fern, context.maple, :mother, options)
      parent!(context.fern, context.rolo, :father, options)

      relations = Residents.relations(context.fern.id, options)

      assert Enum.map(relations.parents, &{&1.role, &1.parent.name}) ==
               [mother: "Maple", father: "Rolo"]

      assert [%{role: :mother, resident: %{name: "Fern"}}] =
               Residents.relations(context.maple.id, options).young

      assert {:error, %Ash.Error.Invalid{} = error} =
               Residents.record_parent(
                 %{resident_id: context.fern.id, parent_id: context.sage.id, role: :mother},
                 options
               )

      assert Exception.message(error) =~ "has a parent in this role already"
    end

    test "does not make a resident its own parent, or a parent of its own parent", context do
      options = context.options
      parent!(context.fern, context.maple, :mother, options)
      parent!(context.sage, context.fern, :mother, options)

      assert {:error, %Ash.Error.Invalid{} = error} =
               Residents.record_parent(
                 %{resident_id: context.maple.id, parent_id: context.maple.id, role: :mother},
                 options
               )

      assert Exception.message(error) =~ "cannot be the resident itself"

      # Sage is the young of Fern, who is the young of Maple.
      for young <- [context.fern, context.sage] do
        assert {:error, %Ash.Error.Invalid{} = error} =
                 Residents.record_parent(
                   %{resident_id: context.maple.id, parent_id: young.id, role: :father},
                   options
                 )

        assert Exception.message(error) =~ "is one of the young of this resident"
      end
    end

    test "goes when a member removes it, and can come again", context do
      options = context.options
      link = parent!(context.fern, context.maple, :mother, options)
      before = DateTime.utc_now()

      assert :ok = Residents.remove_parent(link, options)
      assert Residents.relations(context.fern.id, options).parents == []

      assert [%{role: :mother}] =
               Residents.relations(context.fern.id, [as_of: before] ++ options).parents

      assert %{role: :mother} = parent!(context.fern, context.maple, :mother, options)
    end

    test "is not for a user of another organisation, or for nobody", context do
      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)

      for actor <- [outsider, nil] do
        assert {:error, %Ash.Error.Forbidden{}} =
                 Residents.record_parent(
                   %{resident_id: context.fern.id, parent_id: context.maple.id, role: :mother},
                   actor: actor,
                   tenant: context.organisation
                 )

        assert Residents.relations(context.fern.id, actor: actor, tenant: context.organisation) ==
                 nil
      end
    end
  end

  describe "a family" do
    test "has a name that no other family has, and its members", context do
      options = context.options
      litter = Residents.name_family!("The spring litter", options)

      assert {:error, %Ash.Error.Invalid{}} = Residents.name_family("The spring litter", options)

      for resident <- [context.fern, context.sage] do
        Residents.add_to_family!(%{resident_id: resident.id, family_id: litter.id}, options)
      end

      assert {:error, %Ash.Error.Invalid{} = error} =
               Residents.add_to_family(
                 %{resident_id: context.fern.id, family_id: litter.id},
                 options
               )

      assert Exception.message(error) =~ "is in this family already"

      assert [%{family: %{name: "The spring litter"}}] =
               Residents.relations(context.fern.id, options).families
    end
  end

  describe "a group" do
    test "has words from the parent links of its members", context do
      options = context.options

      for young <- [context.fern, context.sage] do
        parent!(young, context.maple, :mother, options)
        parent!(young, context.rolo, :father, options)
      end

      family = group!([context.maple, context.rolo, context.fern, context.sage], options)
      assert words(family, options) == "Mother, father and two daughters"

      sisters = group!([context.fern, context.sage, context.basil], options)
      assert words(sisters, options) == "Sisters and an unrelated male"
    end

    test "has words from a family with no known parent", context do
      options = context.options
      litter = Residents.name_family!("The spring litter", options)

      for resident <- [context.fern, context.sage] do
        Residents.add_to_family!(%{resident_id: resident.id, family_id: litter.id}, options)
      end

      assert words(group!([context.fern, context.sage], options), options) == "Sisters"
    end

    test "has no words when no member is related, and the words of a member when given",
         context do
      options = context.options
      group = group!([context.maple, context.basil], options)
      assert words(group, options) == nil

      {:ok, _} = Residents.revise_group(group, %{description: "Bonded at intake"}, options)
      assert words(group, options) == "Bonded at intake"

      # With no words of a member, the calculated ones apply again.
      {:ok, group} = Residents.group_with_facts(group.id, options)
      {:ok, _} = Residents.revise_group(group, %{description: nil}, options)
      assert words(group, options) == nil
    end

    test "has the names of its members for a name, or a name of its own", context do
      options = context.options
      group = group!([context.sage, context.fern, context.basil], options)

      {:ok, loaded} = Residents.group_with_facts(group.id, options)
      assert Residents.group_name(loaded) == "Basil, Fern and Sage"

      {:ok, _} = Residents.revise_group(group, %{name: "The East 1 trio"}, options)
      {:ok, loaded} = Residents.group_with_facts(group.id, options)
      assert Residents.group_name(loaded) == "The East 1 trio"
    end

    test "gets a member and loses one, and keeps who was there at a past instant", context do
      options = context.options
      group = group!([context.fern, context.sage], options)
      before = DateTime.utc_now()

      {:ok, _} =
        Residents.join_group(%{resident_id: context.basil.id, group_id: group.id}, options)

      {:ok, loaded} = Residents.group_with_facts(group.id, options)
      assert Enum.map(loaded.members, & &1.resident.name) == ["Basil", "Fern", "Sage"]

      fern = Enum.find(loaded.members, &(&1.resident.name == "Fern"))
      assert :ok = Residents.leave_group(fern, options)

      {:ok, now} = Residents.group_with_facts(group.id, options)
      assert Enum.map(now.members, & &1.resident.name) == ["Basil", "Sage"]

      {:ok, then} = Residents.group_with_facts(group.id, [as_of: before] ++ options)
      assert Enum.map(then.members, & &1.resident.name) == ["Fern", "Sage"]

      assert {:error, %Ash.Error.Invalid{} = error} =
               Residents.join_group(%{resident_id: context.basil.id, group_id: group.id}, options)

      assert Exception.message(error) =~ "is in this group already"
    end

    test "lets a resident be in more than one group at one time", context do
      options = context.options
      pair = group!([context.fern, context.sage], options, %{name: "The pair"})
      quarantine = group!([context.fern, context.basil], options, %{name: "Quarantine"})

      names =
        context.fern.id
        |> Residents.relations(options)
        |> Map.fetch!(:groups)
        |> Enum.map(fn {_membership, group} -> Residents.group_name(group) end)
        |> Enum.sort()

      assert names == ["Quarantine", "The pair"]
      assert pair.id != quarantine.id
    end

    test "has a kind from the list of the organisation", context do
      options = context.options

      {:ok, kind} =
        Rescord.Lists.add_local_value(:group_kind, "Bonded pair",
          actor: context.root,
          tenant: context.organisation
        )

      group = group!([context.fern, context.sage], options, %{kind_id: kind.id})

      {:ok, loaded} = Residents.group_with_facts(group.id, options)
      assert to_string(loaded.kind.label) == "Bonded pair"
    end

    test "is not there after it closes, and was there at a past instant", context do
      options = context.options
      group = group!([context.fern, context.sage], options)
      before = DateTime.utc_now()

      assert :ok = Residents.close_group(group, options)
      assert {:ok, nil} = Residents.group_with_facts(group.id, options)
      assert {:ok, []} = Residents.groups_with_facts(options)

      assert {:ok, %{members: [_fern, _sage]}} =
               Residents.group_with_facts(group.id, [as_of: before] ++ options)
    end

    test "is not there at all when one of its first members is not a resident", context do
      assert {:error, _error} =
               Residents.form_group(
                 %{resident_ids: [context.fern.id, Ash.UUID.generate()]},
                 context.options
               )

      assert {:ok, []} = Residents.groups_with_facts(context.options)
    end

    test "is not for a user of another organisation, or for nobody", context do
      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)
      group = group!([context.fern, context.sage], context.options)

      for actor <- [outsider, nil] do
        options = [actor: actor, tenant: context.organisation]

        assert {:ok, nil} = Residents.group_with_facts(group.id, options)
        assert {:ok, []} = Residents.groups_with_facts(options)

        assert {:error, %Ash.Error.Forbidden{}} =
                 Residents.form_group(%{resident_ids: [context.fern.id]}, options)

        assert {:error, %Ash.Error.Forbidden{}} = Residents.close_group(group, options)
      end

      assert {:ok, [_group]} = Residents.groups_with_facts(context.options)
    end
  end
end
