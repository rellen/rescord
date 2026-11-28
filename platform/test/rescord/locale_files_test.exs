defmodule Rescord.LocaleFilesTest do
  @moduledoc """
  Holds the files of the locales to the release of `localize` in the lock
  (ADR 0075).

  `priv/localize/locales` has a file for each locale that Rescord offers.
  `localize` has the data of `en` only, and a locale with no file, or with a
  file of another release, gets the forms of `en` with no error. After an
  update of `localize`, run `mix localize.download_locales` and commit the
  files.
  """

  use ExUnit.Case, async: true

  alias Localize.Locale.Provider

  @directory Application.app_dir(:rescord, "priv/localize/locales")

  # The file of a locale that Rescord offers: `en-US` is `en`.
  defp file_name("en-US"), do: "en"
  defp file_name(tag), do: tag

  test "Localize reads the locales from the files of Rescord" do
    assert Provider.locale_cache_dir() == @directory
  end

  test "each locale that Rescord offers has a file, and Localize names it" do
    supported = Enum.map(Localize.supported_locales(), &Atom.to_string/1)

    for {tag, _name} <- Rescord.Accounts.locales() do
      name = file_name(tag)
      assert File.regular?(Path.join(@directory, name <> ".etf")), "no file for #{tag}"
      assert name in supported, "config :localize does not name #{name}"
    end
  end

  test "each file is the one of this release of Localize" do
    hashes = Provider.locale_hashes()
    assert is_map(hashes), "this build of localize has no list of hashes"
    expected = Map.new(hashes, fn {locale, hash} -> {Atom.to_string(locale), hash} end)

    files = Path.wildcard(Path.join(@directory, "*.etf"))
    assert files != []

    for path <- files do
      name = Path.basename(path, ".etf")

      assert :crypto.hash(:sha256, File.read!(path)) == expected[name],
             "#{name}.etf is not the file of localize #{Application.spec(:localize, :vsn)}: " <>
               "run `mix localize.download_locales` and commit the files"
    end
  end

  test "a locale has its own forms, and not the ones of `en`" do
    date = ~D[2026-11-16]

    assert {:ok, "November 16, 2026"} =
             Localize.Date.to_string(date, locale: "en-US", format: :long)

    assert {:ok, "16 November 2026"} =
             Localize.Date.to_string(date, locale: "en-AU", format: :long)

    assert {:ok, "18:30"} = Localize.Time.to_string(~T[18:30:00], locale: "en-GB", format: :short)
    assert {:ok, "12,34,567"} = Localize.Number.to_string(1_234_567, locale: "en-IN")
  end
end
