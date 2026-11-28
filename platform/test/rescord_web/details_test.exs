defmodule RescordWeb.DetailsTest do
  @moduledoc """
  Holds a rule for each `<details>` of a page: it has an id.

  A person opens a `<details>`, and `keepDetailsOpen` of `shoddy_phoenix` keeps it open
  when LiveView draws the page again. LiveView finds the same element in the
  new page by its id. Without one, a paragraph that comes above it, such as
  the words of a refusal, makes a new element of it, and it closes with what
  the person typed inside.

  `RescordWeb.Features.JournalTest` holds this in a browser for one form.
  """

  use ExUnit.Case, async: true

  @pages Path.wildcard("lib/rescord_web/live/*.ex")

  test "there are pages to read" do
    assert length(@pages) > 5
  end

  for page <- @pages do
    test "each <details> of #{Path.basename(page)} has an id" do
      # The tag of each <details>: the text from its name to its <summary>.
      # The formatter can put its attributes in any order, and on more lines.
      [_before | tags] =
        unquote(page)
        |> File.read!()
        |> String.split(~r/<details(?=[\s>])/)

      without =
        tags
        |> Enum.map(&(&1 |> String.split("<summary") |> hd()))
        |> Enum.reject(&(&1 =~ ~r/\sid=/))

      assert without == []
    end
  end
end
