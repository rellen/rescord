defmodule Rescord.HistoryTest do
  @moduledoc """
  Holds how the versions of a record read as changes (ADR 0035). The module
  under test has no database, so these tests run beside others.
  """

  use ExUnit.Case, async: true

  alias Rescord.History

  doctest History

  defp version(id, from, to, more \\ %{}) do
    Map.merge(%{id: id, valid_at: %{lower: from, upper: to}, user_id: "user"}, more)
  end

  @eight ~U[2026-11-16 08:00:00Z]
  @nine ~U[2026-11-16 09:00:00Z]
  @ten ~U[2026-11-16 10:00:00Z]

  test "a record with one version that has no end started, and that is all" do
    assert [%{kind: :started, at: @eight, user_id: "user", record: %{id: "a"}}] =
             History.changes([version("a", @eight, nil)])
  end

  test "each later version of a record is a change, by the user of that version" do
    versions = [
      version("a", @nine, nil, %{user_id: "second", place: "west"}),
      version("a", @eight, @nine, %{user_id: "first", place: "east"})
    ]

    assert [
             %{kind: :started, at: @eight, user_id: "first", record: %{place: "east"}},
             %{kind: :changed, at: @nine, user_id: "second", record: %{place: "west"}}
           ] = History.changes(versions)
  end

  test "a last version with an end is where the record ended, with no person" do
    assert [
             %{kind: :started, at: @eight},
             %{kind: :ended, at: @nine, user_id: nil, record: %{id: "a"}}
           ] = History.changes([version("a", @eight, @nine)])
  end

  test "a version that is archived is where the record ended, by its user" do
    versions = [
      version("a", @eight, @nine),
      version("a", @nine, nil, %{archived_at: @nine, user_id: "remover"})
    ]

    assert [%{kind: :started}, %{kind: :ended, at: @nine, user_id: "remover"}] =
             History.changes(versions)
  end

  test "the changes of several records are in the order of time" do
    versions = [
      version("b", @nine, @ten),
      version("a", @eight, nil)
    ]

    assert Enum.map(History.changes(versions), &{&1.record.id, &1.kind, &1.at}) == [
             {"a", :started, @eight},
             {"b", :started, @nine},
             {"b", :ended, @ten}
           ]
  end

  test "no version is no change" do
    assert History.changes([]) == []
  end
end
