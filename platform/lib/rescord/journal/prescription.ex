defmodule Rescord.Journal.Prescription do
  @moduledoc """
  The medication that a journal entry of the kind `prescription` gives a
  resident: what, how much and how often in words, the route, and the days.
  A dose that a member gave can name its prescription.
  """

  use Rescord.Journal.Detail,
    table: "prescriptions",
    accept: [:medication, :dose, :route, :starts_on, :ends_on]

  attributes do
    attribute :medication, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 120
    end

    attribute :dose, :string do
      public? true
      constraints max_length: 200
      description "How much and how often, in words: 0.2 mL two times each day"
    end

    attribute :route, Rescord.Journal.Route do
      public? true
    end

    attribute :starts_on, :date do
      public? true
    end

    attribute :ends_on, :date do
      public? true
    end
  end

  # The days of a prescription run forwards (ADR 0115). A correction can give
  # one of the two days, so the check is of the record as it will be.
  validations do
    validate compare(:ends_on, greater_than_or_equal_to: :starts_on),
      where: [present([:starts_on, :ends_on])],
      message: "must be on or after the first day"
  end
end
