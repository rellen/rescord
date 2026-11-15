defmodule RescordWeb.ResidentWordsTest do
  @moduledoc """
  Holds the words of a page to the fixed lists of a resident: each value of
  a list has a word, and the words name no value that the list does not
  have. A new value of a list then fails here until it has a word.
  """

  use ExUnit.Case, async: true

  alias Rescord.Residents
  alias RescordWeb.ResidentWords

  for {list, type, word} <- [
        {:status, Residents.Status, :status},
        {:sex, Residents.Sex, :sex},
        {:desex, Residents.DesexStatus, :desex},
        {:arrival, Residents.ArrivalKind, :arrival},
        {:departure, Residents.DepartureKind, :departure}
      ] do
    test "each value of #{inspect(type)} has a word" do
      values = unquote(type).values()

      assert Enum.sort(ResidentWords.values(unquote(list))) == Enum.sort(values)

      for value <- values do
        word = apply(ResidentWords, unquote(word), [value])
        assert is_binary(word)
        refute word =~ "_"
      end
    end
  end

  test "each status has a kind of state that the page can draw" do
    for status <- Residents.Status.values() do
      assert ResidentWords.status_kind(status) in ~w(ok alert info none)
    end
  end

  test "an option of a select has a word and the text of its value" do
    assert {"Stray", "stray"} in ResidentWords.options(:arrival)
    assert {"Not known", "unknown"} in ResidentWords.options(:sex)
  end

  test "a date is in words" do
    assert ResidentWords.date(~D[2026-09-12]) == "12 September 2026"
    assert ResidentWords.date(nil) == nil
  end

  describe "the age" do
    test "is in days, then months, then years" do
      today = ~D[2026-11-15]

      assert ResidentWords.age(~D[2026-11-14], today) == "1 day"
      assert ResidentWords.age(~D[2026-11-01], today) == "14 days"
      assert ResidentWords.age(~D[2026-10-15], today) == "1 month"
      assert ResidentWords.age(~D[2025-03-01], today) == "20 months"
      assert ResidentWords.age(~D[2024-11-16], today) == "23 months"
      assert ResidentWords.age(~D[2024-11-15], today) == "2 years"
      assert ResidentWords.age(~D[2020-01-01], today) == "6 years"
    end

    test "is not there with no date of birth, or with one after today" do
      assert ResidentWords.age(nil, ~D[2026-11-15]) == nil
      assert ResidentWords.age(~D[2026-12-01], ~D[2026-11-15]) == nil
    end
  end
end
