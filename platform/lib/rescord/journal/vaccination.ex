defmodule Rescord.Journal.Vaccination do
  @moduledoc "The vaccine that a journal entry of the kind `vaccination` records."

  use Rescord.Journal.Detail, table: "vaccinations", accept: [:vaccine]

  attributes do
    attribute :vaccine, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 120
    end
  end
end
