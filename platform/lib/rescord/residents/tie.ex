defmodule Rescord.Residents.Tie do
  @moduledoc """
  A tie between a resident and a value of a list of its organisation, for a
  dimension of which a resident has more than one value: the breed, the
  colour and the temperament (`docs/domain.md`, section 5.2).

      defmodule Rescord.Residents.ResidentBreed do
        use Rescord.Residents.Tie,
          table: "resident_breeds",
          value: :breed,
          list: Rescord.Lists.Breed
      end

  A resident has each value one time. The removal of a tie ends its period,
  so the same value can come again later, and a read as of a past instant
  still gives the tie.
  """

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)
    value = Keyword.fetch!(opts, :value)
    list = Keyword.fetch!(opts, :list)
    value_id = :"#{value}_id"

    quote do
      use Rescord.Residents.Fact, table: unquote(table), archive?: false

      actions do
        defaults [:read, :destroy]

        create :add do
          accept [:resident_id, unquote(value_id)]
        end
      end

      relationships do
        belongs_to unquote(value), unquote(list) do
          allow_nil? false
          public? true
          temporal_keys {:valid_at, :valid_at}
        end
      end

      identities do
        identity :unique_value, [:resident_id, unquote(value_id)],
          message: "has this value already"
      end
    end
  end
end
