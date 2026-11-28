defmodule Rescord.Accounts.FieldErrorsTest do
  @moduledoc """
  Holds `Rescord.Accounts.field_errors/1`: the messages of an error that a
  form shows at its fields (ADR 0111).
  """

  use ExUnit.Case, async: true

  doctest Rescord.Accounts, only: [field_errors: 1]

  alias Ash.Error.Changes.{InvalidAttribute, Required}
  alias Rescord.Accounts

  test "gives each message with a field, in the words of the problems of the page" do
    error = %{
      errors: [
        Required.exception(field: :species_id),
        InvalidAttribute.exception(field: :value, message: "is invalid"),
        Ash.Error.Forbidden.Policy.exception([])
      ]
    }

    assert Accounts.field_errors(error) == [
             species_id: "Species is required",
             value: "Value is invalid"
           ]

    for {_field, message} <- Accounts.field_errors(error),
        do: assert(message in Accounts.error_messages(error))
  end

  test "finds the errors inside the error of a hook" do
    inner = %{errors: [Required.exception(field: :arrived_on)]}

    assert Accounts.field_errors(%{errors: [inner]}) == [arrived_on: "Arrived on is required"]
  end

  test "gives nothing for an error with no field, or for no error" do
    assert Accounts.field_errors(nil) == []
    assert Accounts.field_errors(%{errors: [Ash.Error.Forbidden.Policy.exception([])]}) == []
  end
end
