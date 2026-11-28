defmodule Rescord.Accounts.ErrorMessagesTest do
  @moduledoc """
  Holds the words that a page shows for an error of an action: each names
  its field in words, has the values of its rule, and shows no name of a
  module.
  """

  use ExUnit.Case, async: true

  alias Ash.Error.Changes.{InvalidAttribute, Required, StaleRecord}
  alias Rescord.Accounts

  defp messages(errors), do: Accounts.error_messages(%Ash.Error.Invalid{errors: errors})

  test "a message names its field in words, with no `_id`" do
    assert messages([InvalidAttribute.exception(field: :kind_id, message: "is not in the list")]) ==
             ["Kind is not in the list"]
  end

  test "a message has the values of its rule" do
    error =
      InvalidAttribute.exception(
        field: :task_days_ahead,
        message: "must be greater than or equal to %{min}",
        vars: [min: 1]
      )

    assert messages([error]) == ["Task days ahead must be greater than or equal to 1"]

    # A list is shown as Elixir writes it, and not as letters.
    between =
      InvalidAttribute.exception(
        field: :weekdays,
        message: "must be one of %{list}",
        vars: [list: [1, 2]]
      )

    assert messages([between]) == ["Weekdays must be one of [1, 2]"]
  end

  test "a validation of a hook names its field in a list, and an error can hold errors" do
    alias Ash.Error.Changes.InvalidChanges

    changes = InvalidChanges.exception(fields: [:location], message: "has residents in it")
    assert messages([changes]) == ["Location has residents in it"]

    inner = %Ash.Error.Invalid{errors: [changes]}
    assert messages([inner]) == ["Location has residents in it"]
  end

  test "a value that is not there says that it is required" do
    assert messages([Required.exception(field: :title, type: :attribute)]) == [
             "Title is required"
           ]
  end

  test "a record that changed a moment ago says so, with no name of a module" do
    assert [words] = messages([StaleRecord.exception(resource: Rescord.Tasks.Task, filter: %{})])
    assert words =~ "Somebody changed this a moment ago"
    refute words =~ "Rescord"
  end

  describe "an error of Rescord itself (ADR 0077, E2)" do
    alias Rescord.Accounts.Errors.InvalidTime
    alias Rescord.Storage.Errors.RefusedFile

    test "has its words alone, or in an error of an action" do
      error = InvalidTime.exception(reason: :after_now)

      assert Accounts.error_messages(error) == ["The time cannot be after now"]
      assert messages([error]) == ["The time cannot be after now"]
    end

    test "says its words after the name of its field" do
      error = RefusedFile.exception(reason: :empty, field: :content)
      assert messages([error]) == ["Content is an empty file"]
    end

    test "has no bread crumbs of Ash in front of its words" do
      error =
        [reason: :not_a_time]
        |> InvalidTime.exception()
        |> Ash.Error.to_error_class(bread_crumbs: ["Returned from bulk create"])

      assert Exception.message(error) =~ "Bread Crumbs"

      assert Accounts.error_messages(error) == [
               "The time is not a date and a time of this time zone"
             ]
    end

    test "is in the class that it names, and the log has its reason" do
      error = Ash.Error.to_error_class(RefusedFile.exception(reason: :busy, field: :content))

      assert %Ash.Error.Invalid{errors: [%RefusedFile{}]} = error

      assert Rescord.Log.reason(error) ==
               "invalid: Rescord.Storage.Errors.RefusedFile(field: :content, reason: :busy)"
    end
  end

  test "a thing that is no error of an action has plain words" do
    assert Accounts.error_messages(:oops) == ["That did not work"]
  end
end
