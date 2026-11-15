defmodule Rescord.Lists.BaseList do
  @moduledoc """
  The base list of a dimension: the shared values, which all organisations
  read (`docs/domain.md`, section 7.2, and ADR 0016).

  A base list is outside the schemas of the organisations. A root user adds a
  value and gives a value a new name. Each user who is signed in reads the
  list. No action removes a value yet.

      defmodule Rescord.Lists.Base.Species do
        use Rescord.Lists.BaseList, table: "base_species"
      end
  """

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)

    quote do
      use Rescord.Resource,
        domain: Rescord.Lists,
        shared?: true,
        authorizers: [Ash.Policy.Authorizer]

      postgres do
        table unquote(table)
      end

      paper_trail do
        belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
      end

      actions do
        defaults [:read]

        create :add do
          description "Adds a shared value"
          accept [:name]
        end

        update :rename do
          description "Gives the shared value a new name"
          accept [:name]
        end
      end

      policies do
        # A root user can do anything. Nobody else writes a base list.
        bypass actor_attribute_equals(:root?, true) do
          authorize_if always()
        end

        policy action_type(:read) do
          authorize_if actor_present()
        end
      end

      attributes do
        uuid_primary_key :id

        attribute :name, :ci_string do
          allow_nil? false
          public? true
          constraints min_length: 1, max_length: 60
        end
      end

      identities do
        identity :unique_name, [:name], message: "is in the list already"
      end
    end
  end
end
