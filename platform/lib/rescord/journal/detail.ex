defmodule Rescord.Journal.Detail do
  @moduledoc """
  The parts that each resource with the facts of one kind of journal entry
  has: a table in the schema of the organisation, the entry that it belongs
  to, the user in its paper trail, and the policy.

      defmodule Rescord.Journal.Vaccination do
        use Rescord.Journal.Detail, table: "vaccinations", accept: [:vaccine]

        attributes do
          attribute :vaccine, :string, allow_nil?: false, public?: true
        end
      end

  An entry has one such record at most. `Rescord.Journal.JournalEntry`
  writes it: `set` makes it and `change` corrects it, and no role has a
  grant to write it in another way.
  """

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)
    accept = Keyword.fetch!(opts, :accept)

    quote do
      use Rescord.Resource,
        domain: Rescord.Journal,
        authorizers: [Ash.Policy.Authorizer]

      postgres do
        table unquote(table)
      end

      paper_trail do
        belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
      end

      actions do
        defaults [:read]

        create :set do
          accept [:entry_id | unquote(accept)]
        end

        update :change do
          accept unquote(accept)
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
      end

      relationships do
        belongs_to :entry, Rescord.Journal.JournalEntry do
          allow_nil? false
          public? true
          temporal_keys {:valid_at, :valid_at}
        end
      end

      identities do
        identity :unique_entry, [:entry_id]
      end
    end
  end
end
