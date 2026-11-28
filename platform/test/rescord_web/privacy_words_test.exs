defmodule RescordWeb.PrivacyWordsTest do
  @moduledoc "Holds the words of the requests to erase data (ADR 0105)."

  use ExUnit.Case, async: true

  alias RescordWeb.PrivacyWords

  doctest PrivacyWords

  test "each way that a request comes has words" do
    for way <- [:own_page, :email, :letter, :in_person, :account, :automatic],
        do: assert(is_binary(PrivacyWords.how(way)))
  end
end
