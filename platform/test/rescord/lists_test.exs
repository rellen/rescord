defmodule Rescord.ListsTest do
  @moduledoc """
  Holds the lists of values: the base list of a dimension, which all
  organisations share, and the list of one organisation (ADR 0016, ADR 0025).

  These are the first resources with a table that are temporal, so the tests
  also read a list as of a past instant.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures

  alias Rescord.Lists

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)

    {:ok, root: root, organisation: organisation, administrator: administrator, member: member}
  end

  defp labels(values), do: Enum.map(values, &to_string(&1.label))
  defp names(values), do: Enum.map(values, &to_string(&1.name))

  describe "the dimensions" do
    test "are the ones that Rescord has so far, in the order of a page" do
      assert Keyword.keys(Lists.dimensions()) ==
               [
                 :species,
                 :breed,
                 :colour,
                 :size_class,
                 :coat,
                 :temperament,
                 :identifier_kind,
                 :group_kind,
                 :location_kind,
                 :condition,
                 :measure_kind,
                 :procedure_kind,
                 :unit,
                 :task_kind
               ]
    end

    test "have a key for the text of a parameter, and make no atom from other text" do
      assert Lists.dimension("size_class") == {:ok, :size_class}
      assert Lists.dimension("no_such_list") == :error
      assert Lists.dimension(nil) == :error
      assert Lists.shared_values(:no_such_list, authorize?: false) == {:error, :no_such_dimension}
    end
  end

  describe "a base list" do
    test "gets a value from a root user, and each user who is signed in reads it", context do
      assert {:ok, _} = Lists.add_shared_value(:species, "Guinea pig", actor: context.root)
      assert {:ok, _} = Lists.add_shared_value(:species, "Dog", actor: context.root)

      for user <- [context.root, context.administrator, context.member, user!()] do
        assert {:ok, values} = Lists.shared_values(:species, actor: user)
        assert names(values) == ["Dog", "Guinea pig"]
      end
    end

    test "is not there for a person who is not signed in", context do
      Lists.add_shared_value(:species, "Guinea pig", actor: context.root)

      # A read that the policy refuses is empty, and is not an error.
      assert {:ok, []} = Lists.shared_values(:species, actor: nil)
      assert {:ok, [_value]} = Lists.shared_values(:species, actor: context.member)
    end

    test "gets no value from a user who is not a root user", context do
      for user <- [context.administrator, context.member, user!()] do
        assert {:error, %Ash.Error.Forbidden{}} =
                 Lists.add_shared_value(:species, "Rabbit", actor: user)
      end

      assert {:ok, []} = Lists.shared_values(:species, actor: context.root)
    end

    test "has each name one time, whatever its case", context do
      assert {:ok, _} = Lists.add_shared_value(:colour, "Tricolour", actor: context.root)

      assert {:error, %Ash.Error.Invalid{} = error} =
               Lists.add_shared_value(:colour, "tricolour", actor: context.root)

      assert Exception.message(error) =~ "is in the list already"

      # The same name in another dimension is another value.
      assert {:ok, _} = Lists.add_shared_value(:coat, "Tricolour", actor: context.root)
    end

    test "keeps the old name of a value for a read as of a past instant", context do
      {:ok, value} = Lists.add_shared_value(:breed, "Abysinian", actor: context.root)
      before = DateTime.utc_now()

      assert {:ok, _} =
               Lists.rename_shared_value(:breed, value.id, "Abyssinian", actor: context.root)

      assert {:ok, now} = Lists.shared_values(:breed, actor: context.root)
      assert names(now) == ["Abyssinian"]

      assert {:ok, then} = Lists.shared_values(:breed, actor: context.root, as_of: before)
      assert names(then) == ["Abysinian"]
    end
  end

  describe "the list of an organisation" do
    setup context do
      {:ok, guinea_pig} = Lists.add_shared_value(:species, "Guinea pig", actor: context.root)
      {:ok, dog} = Lists.add_shared_value(:species, "Dog", actor: context.root)

      options = [actor: context.administrator, tenant: context.organisation]
      {:ok, guinea_pig: guinea_pig, dog: dog, options: options}
    end

    test "holds a shared value under the name of the base list, and a local value under its own",
         context do
      assert {:ok, shared} =
               Lists.use_shared_value(:species, context.guinea_pig.id, context.options)

      assert {:ok, local} = Lists.add_local_value(:species, "Degu", context.options)

      assert shared.base_id == context.guinea_pig.id
      assert is_nil(shared.name)
      assert is_nil(local.base_id)

      assert {:ok, values} = Lists.values(:species, context.options)
      assert labels(values) == ["Degu", "Guinea pig"]
    end

    test "is there for each member and for a root user", context do
      Lists.add_local_value(:species, "Degu", context.options)

      for user <- [context.member, context.administrator, context.root] do
        assert {:ok, values} = Lists.values(:species, actor: user, tenant: context.organisation)
        assert labels(values) == ["Degu"]
      end
    end

    test "gets no value from a member", context do
      options = [actor: context.member, tenant: context.organisation]

      assert {:error, %Ash.Error.Forbidden{}} = Lists.add_local_value(:species, "Degu", options)

      assert {:error, %Ash.Error.Forbidden{}} =
               Lists.use_shared_value(:species, context.dog.id, options)

      assert {:ok, []} = Lists.values(:species, context.options)
    end

    test "is apart from the list of another organisation", context do
      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)

      Lists.add_local_value(:species, "Degu", context.options)

      # The outsider has no role here: a read is empty, and a write is refused.
      assert {:ok, []} = Lists.values(:species, actor: outsider, tenant: context.organisation)

      assert {:error, %Ash.Error.Forbidden{}} =
               Lists.add_local_value(:species, "Hen",
                 actor: outsider,
                 tenant: context.organisation
               )

      # The list of the other organisation does not have the value.
      assert {:ok, []} = Lists.values(:species, actor: outsider, tenant: other)

      # Both can have a local value of the same name.
      assert {:ok, _} = Lists.add_local_value(:species, "Degu", actor: outsider, tenant: other)
    end

    test "has each shared value and each local name one time", context do
      assert {:ok, _} = Lists.use_shared_value(:species, context.dog.id, context.options)
      assert {:ok, _} = Lists.add_local_value(:species, "Degu", context.options)

      assert {:error, %Ash.Error.Invalid{}} =
               Lists.use_shared_value(:species, context.dog.id, context.options)

      assert {:error, %Ash.Error.Invalid{}} =
               Lists.add_local_value(:species, "degu", context.options)

      assert {:ok, values} = Lists.values(:species, context.options)
      assert length(values) == 2
    end

    test "says which shared values the organisation does not use yet", context do
      Lists.use_shared_value(:species, context.dog.id, context.options)

      assert {:ok, unused} = Lists.unused_shared_values(:species, context.options)
      assert names(unused) == ["Guinea pig"]
    end

    test "refuses a row that is a shared value and a local value, or neither", context do
      both = %{base_id: context.dog.id, name: "Dog of ours"}

      for attributes <- [both, %{}] do
        assert_raise Ash.Error.Invalid, fn ->
          Ash.Seed.seed!(Lists.Species, attributes, tenant: context.organisation)
        end
      end
    end

    test "gives a local value a new name, and keeps the old one for a past instant", context do
      {:ok, value} = Lists.add_local_value(:temperament, "Shy", context.options)
      before = DateTime.utc_now()

      assert {:ok, _} =
               Lists.rename_local_value(
                 :temperament,
                 value.id,
                 "Shy with people",
                 context.options
               )

      assert {:ok, now} = Lists.values(:temperament, context.options)
      assert labels(now) == ["Shy with people"]

      assert {:ok, then} = Lists.values(:temperament, [as_of: before] ++ context.options)
      assert labels(then) == ["Shy"]
    end

    test "does not give a shared value a name of its own", context do
      {:ok, value} = Lists.use_shared_value(:species, context.dog.id, context.options)

      assert {:error, %Ash.Error.Invalid{} = error} =
               Lists.rename_local_value(:species, value.id, "Hound", context.options)

      assert Exception.message(error) =~ "is a shared value"
    end

    test "follows a new name of the base list", context do
      Lists.use_shared_value(:species, context.dog.id, context.options)
      before = DateTime.utc_now()

      {:ok, _} =
        Lists.rename_shared_value(:species, context.dog.id, "Domestic dog", actor: context.root)

      assert {:ok, now} = Lists.values(:species, context.options)
      assert labels(now) == ["Domestic dog"]

      assert {:ok, then} = Lists.values(:species, [as_of: before] ++ context.options)
      assert labels(then) == ["Dog"]
    end

    test "names in its versions the user who made each change", context do
      {:ok, value} = Lists.add_local_value(:coat, "Rough", context.options)

      {:ok, _} =
        Lists.rename_local_value(:coat, value.id, "Rough, with rosettes", context.options)

      version = AshPaperTrail.Resource.Info.version_resource(Lists.Coat)

      versions =
        version
        |> Ash.read!(tenant: context.organisation, authorize?: false)
        |> Enum.filter(&(&1.id == value.id))

      assert length(versions) == 2
      assert Enum.all?(versions, &(&1.user_id == context.administrator.id))

      assert Enum.sort(Enum.map(versions, & &1.version_action_name)) == [:add_local, :rename]
    end
  end

  describe "a value that is retired" do
    setup context do
      options = [actor: context.administrator, tenant: context.organisation]
      {:ok, rex} = Lists.add_local_value(:breed, "Rex", options)
      {:ok, sheltie} = Lists.add_local_value(:breed, "Sheltie", options)
      {:ok, rex: rex, sheltie: sheltie, options: options}
    end

    test "stays in the list, and no form offers it", context do
      assert {:ok, %{retired: true}} = Lists.retire_value(:breed, context.rex.id, context.options)

      assert {:ok, values} = Lists.values(:breed, context.options)

      assert Enum.map(values, &{to_string(&1.label), &1.retired}) ==
               [{"Rex", true}, {"Sheltie", false}]

      assert {:ok, offered} = Lists.offered_values(:breed, context.options)
      assert labels(offered) == ["Sheltie"]
    end

    test "comes again when an administrator restores it", context do
      {:ok, _} = Lists.retire_value(:breed, context.rex.id, context.options)
      before = DateTime.utc_now()

      assert {:ok, %{retired: false}} =
               Lists.restore_value(:breed, context.rex.id, context.options)

      assert {:ok, offered} = Lists.offered_values(:breed, context.options)
      assert labels(offered) == ["Rex", "Sheltie"]

      # At the instant before, it was retired.
      assert {:ok, then} = Lists.offered_values(:breed, [as_of: before] ++ context.options)
      assert labels(then) == ["Sheltie"]
    end

    test "is not a thing that a member can do, and no input sets it", context do
      member = [actor: context.member, tenant: context.organisation]

      assert {:error, %Ash.Error.Forbidden{}} = Lists.retire_value(:breed, context.rex.id, member)

      {:ok, _} = Lists.retire_value(:breed, context.rex.id, context.options)

      assert {:error, %Ash.Error.Forbidden{}} =
               Lists.restore_value(:breed, context.rex.id, member)

      for action <- [:add_local, :add_shared, :rename, :retire, :restore] do
        refute :retired in Ash.Resource.Info.action(Lists.Breed, action).accept
      end
    end
  end

  describe "the grants of the lists" do
    test "are in the grants of each role" do
      assert Rescord.Lists.Grants in Rescord.Accounts.Grants.sources()

      assert {:ok, :all} = Rescord.Accounts.Grants.scope(:administrator, Lists.Breed, :add_local)
      assert {:ok, :all} = Rescord.Accounts.Grants.scope(:member, Lists.Breed, :read)
      assert :none = Rescord.Accounts.Grants.scope(:member, Lists.Breed, :add_local)

      assert Lists.role_can_change?(:root)
      assert Lists.role_can_change?(:administrator)
      refute Lists.role_can_change?(:member)
      refute Lists.role_can_change?(nil)
    end
  end
end
