defmodule Rescord.Residents.Fact do
  @moduledoc """
  The parts that each resource about one resident has: a table in the schema
  of the organisation, the resident that it is about, the user in its paper
  trail, and the policy.

      defmodule Rescord.Residents.ResidentName do
        use Rescord.Residents.Fact, table: "resident_names"

        # its own attributes, actions and identities
      end

  The resource is temporal (ADR 0012), so a read as of a past instant gives
  the fact as it was then. Its period is inside the period of its resident:
  the database refuses a fact about a resident that is not there.

  ## Options

    * `table` - the name of the table.
    * `archive?` - `false` for a fact whose removal ends its period and leaves
      no row for the time after. Use it where the same fact can come again
      for the same resident, for example the same breed. A removal then has
      no version of its own: the last version ends at the instant of the
      removal. Default `true`.
  """

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)
    archive? = Keyword.get(opts, :archive?, true)

    quote do
      use Rescord.Resource,
        domain: Rescord.Residents,
        archive?: unquote(archive?),
        authorizers: [Ash.Policy.Authorizer]

      postgres do
        table unquote(table)
      end

      paper_trail do
        belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
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
      end

      relationships do
        belongs_to :resident, Rescord.Residents.Resident do
          allow_nil? false
          public? true
          temporal_keys {:valid_at, :valid_at}
        end
      end
    end
  end
end
