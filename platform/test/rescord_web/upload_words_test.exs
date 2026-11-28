defmodule RescordWeb.UploadWordsTest do
  use ExUnit.Case, async: true

  alias RescordWeb.UploadWords

  doctest UploadWords

  test "a HEIC or an AVIF photo by its name or its type, and no other file" do
    assert UploadWords.heif?(%{client_name: "a.heif", client_type: nil})
    assert UploadWords.heif?(%{client_name: "a.avif", client_type: ""})
    assert UploadWords.heif?(%{client_name: "a", client_type: "image/HEIC"})
    refute UploadWords.heif?(%{client_name: "a.pdf", client_type: "application/pdf"})
    refute UploadWords.heif?(%{})
  end

  test "the words of the form for every other refusal" do
    words = fn error -> "form: #{error}" end
    entry = %{client_name: "a.heic", client_type: "image/heic"}

    assert UploadWords.of(:not_accepted, entry, words) == UploadWords.heif()
    assert UploadWords.of(:too_large, entry, words) == "form: too_large"

    assert UploadWords.of(
             :not_accepted,
             %{client_name: "a.html", client_type: "text/html"},
             words
           ) ==
             "form: not_accepted"
  end
end
