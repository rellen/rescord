defmodule Rescord.Lists.OrganisationList do
  @moduledoc """
  The list of one organisation for a dimension: each value that the
  organisation uses (`docs/domain.md`, section 7.2, and ADR 0025).

  A row of the list names a value of the base list, or it is a local value
  with a name of its own. It is never both. A resident thus names one table
  for its species, and that table is in the schema of its organisation.

  An administrator adds a value and gives a local value a new name. Each
  member reads the list.

  An administrator retires a value that the organisation does not want for
  a new choice. A resident that has the value keeps it, and a page still
  shows it: the row stays, with `retired` true. No form offers a retired
  value. An administrator can restore it.

      defmodule Rescord.Lists.Species do
        use Rescord.Lists.OrganisationList, table: "species", base: Rescord.Lists.Base.Species
      end
  """

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)
    base = Keyword.fetch!(opts, :base)

    quote do
      use Rescord.Resource,
        domain: Rescord.Lists,
        authorizers: [Ash.Policy.Authorizer]

      postgres do
        table unquote(table)

        check_constraints do
          check_constraint :name, "one_source",
            check: "(base_id IS NULL) <> (name IS NULL)",
            message: "must be a shared value or a local value, and not both"
        end
      end

      paper_trail do
        belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
      end

      actions do
        defaults [:read]

        create :add_shared do
          description "Adds a value of the base list to the list of the organisation"
          accept [:base_id]
          validate present(:base_id)
        end

        create :add_local do
          description "Adds a local value, with a name of its own"
          accept [:name]
          validate present(:name)
        end

        update :rename do
          description "Gives a local value a new name"
          accept [:name]
          validate present(:name)

          validate absent(:base_id),
            message: "is a shared value, which has the name of the base list"
        end

        update :retire do
          description "Stops the offer of the value for a new choice"
          accept []
          change set_attribute(:retired, true)
        end

        update :restore do
          description "Offers a retired value again"
          accept []
          change set_attribute(:retired, false)
        end
      end

      policies do
        bypass actor_attribute_equals(:root?, true) do
          authorize_if always()
        end

        policy always() do
          authorize_if Rescord.Accounts.Checks.Granted
        end
      end

      attributes do
        uuid_primary_key :id

        attribute :name, :ci_string do
          public? true
          constraints min_length: 1, max_length: 60
        end

        # The name has no `?`, so the column has the same name: the version
        # resource of a temporal resource reads the column by the name of
        # the attribute (ADR 0027).
        attribute :retired, :boolean do
          allow_nil? false
          default false
          public? true
          writable? false
        end
      end

      relationships do
        belongs_to :base, unquote(base) do
          public? true
          temporal_keys {:valid_at, :valid_at}
        end
      end

      calculations do
        # `ref` names each attribute, because a plain name in a macro is not
        # the name that the resource sees.
        calculate :label,
                  :ci_string,
                  expr(
                    if is_nil(^ref(:name)),
                      do: ^ref([:base], :name),
                      else: ^ref(:name)
                  ) do
          public? true
          description "The name of the value: its own, or the one of the base list"
        end
      end

      identities do
        identity :unique_base, [:base_id], message: "is in the list already"
        identity :unique_name, [:name], message: "is in the list already"
      end
    end
  end
end
