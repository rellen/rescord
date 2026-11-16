defmodule Rescord.ResourceTest do
  # What `use Rescord.Resource` gives a resource (ADR 0013), read from the
  # resources of `Rescord.ResourceFixtures` as they compiled. No database.
  use ExUnit.Case, async: true

  alias Rescord.ResourceFixtures.{Bare, Flow, Plain, Shared}

  defp extensions(resource), do: Spark.extensions(resource)

  describe "a resource with the defaults" do
    test "uses Postgres and the repo of Rescord, and names its own table" do
      assert Ash.Resource.Info.data_layer(Plain) == AshPostgres.DataLayer
      assert AshPostgres.DataLayer.Info.repo(Plain) == Rescord.Repo
      assert AshPostgres.DataLayer.Info.table(Plain) == "plains"
    end

    test "is in the schema of an organisation" do
      assert Ash.Resource.Info.multitenancy_strategy(Plain) == :context
    end

    test "is temporal, with the period in :valid_at" do
      assert Ash.Resource.Info.temporal?(Plain)
      assert Ash.Resource.Info.temporal_attribute(Plain) == :valid_at
    end

    test "keeps its paper trail on its own rows, and lists its versions" do
      assert AshPaperTrail.Resource in extensions(Plain)
      assert AshPaperTrail.Resource.Info.temporal_inline?(Plain)
      assert AshPaperTrail.Resource.Info.change_tracking_mode(Plain) == :previous_values
      assert AshPaperTrail.Resource.Info.store_action_name?(Plain)

      version = AshPaperTrail.Resource.Info.version_resource(Plain)
      assert AshPostgres.DataLayer.Info.table(version) == "plains"
    end

    test "archives on a destroy" do
      assert AshArchival.Resource in extensions(Plain)
    end

    test "carries the checks" do
      assert Rescord.Resource.Checks in extensions(Plain)
    end
  end

  describe "the options" do
    test "shared?: true takes the resource out of the schema of an organisation" do
      assert Ash.Resource.Info.multitenancy_strategy(Shared) == nil
      assert Ash.Resource.Info.temporal?(Shared)
    end

    test "each default can be set to false" do
      refute Ash.Resource.Info.temporal?(Bare)
      refute AshPaperTrail.Resource in extensions(Bare)
      refute AshArchival.Resource in extensions(Bare)
      assert Rescord.Resource.Checks in extensions(Bare)
    end

    test "an option that is not a literal true or false does not compile" do
      assert_raise CompileError, ~r/:temporal\? of use Rescord.Resource must be a literal/, fn ->
        Code.compile_string("""
        defmodule Rescord.ResourceTest.NotLiteral do
          use Rescord.Resource, domain: Rescord.ResourceFixtures.Domain, temporal?: :sometimes
        end
        """)
      end
    end
  end

  describe "a temporal resource with a paper trail" do
    test "does not compile with an attribute whose column has another name" do
      error =
        assert_raise Spark.Error.DslError, fn ->
          Code.compile_string("""
          defmodule Rescord.ResourceTest.RenamedColumn do
            use Rescord.Resource, domain: Rescord.ResourceFixtures.Domain

            postgres do
              table "renamed_columns"
            end

            attributes do
              uuid_primary_key :id
              attribute :gone?, :boolean, source: :is_gone
            end
          end
          """)
        end

      assert Exception.message(error) =~ "cannot give an attribute a column of another name"
      assert Exception.message(error) =~ ":gone?"
    end

    test "compiles with such an attribute when it is not temporal" do
      assert [{Rescord.ResourceTest.RenamedPlain, _binary}] =
               Code.compile_string("""
               defmodule Rescord.ResourceTest.RenamedPlain do
                 use Rescord.Resource, domain: Rescord.ResourceFixtures.Domain, temporal?: false

                 postgres do
                   table "renamed_plains"
                 end

                 attributes do
                   uuid_primary_key :id
                   attribute :gone?, :boolean, source: :is_gone
                 end
               end
               """)
               |> Enum.filter(&(elem(&1, 0) == Rescord.ResourceTest.RenamedPlain))
    end
  end

  describe "a resource with a workflow" do
    test "compiles when it is not temporal, and keeps a trail in a table of its own" do
      refute Ash.Resource.Info.temporal?(Flow)
      assert AshStateMachine in extensions(Flow)
      refute AshPaperTrail.Resource.Info.temporal_inline?(Flow)

      version = AshPaperTrail.Resource.Info.version_resource(Flow)
      assert AshPostgres.DataLayer.Info.table(version) == "flows_versions"
    end

    test "adds its own paper trail options to the defaults" do
      assert AshPaperTrail.Resource.Info.ignore_attributes(Flow) == [:id]
      assert AshPaperTrail.Resource.Info.change_tracking_mode(Flow) == :changes_only
      assert AshPaperTrail.Resource.Info.store_action_name?(Flow)
    end

    test "does not compile when it is temporal" do
      error =
        assert_raise Spark.Error.DslError, fn ->
          Code.compile_string("""
          defmodule Rescord.ResourceTest.TemporalFlow do
            use Rescord.Resource,
              domain: Rescord.ResourceFixtures.Domain,
              extensions: [AshStateMachine]

            postgres do
              table "temporal_flows"
            end

            state_machine do
              initial_states [:open]
              default_initial_state :open

              transitions do
                transition :finish, from: :open, to: :done
              end
            end

            actions do
              defaults [:read, create: []]

              update :finish do
                change transition_state(:done)
              end
            end

            attributes do
              uuid_primary_key :id
            end
          end
          """)
        end

      assert Exception.message(error) =~ "cannot be temporal and have a workflow"
      assert Exception.message(error) =~ "AshStateMachine"
      assert Exception.message(error) =~ "temporal?: false"
    end
  end
end
