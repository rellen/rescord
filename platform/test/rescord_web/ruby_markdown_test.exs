defmodule RescordWeb.RubyMarkdownTest do
  @moduledoc """
  Holds `RescordWeb.RubyMarkdown`: the words of a model as HTML with no
  image, no link and no raw HTML, in blocks, with what is open at the end
  closed (ADR 0069).
  """

  use ExUnit.Case, async: true

  alias RescordWeb.RubyMarkdown

  test "gives one block for each paragraph, list, table and heading" do
    text = """
    ## The day

    Five tasks are still open.

    - Feed the goats
    - Weigh Clover

    | Task | Time |
    | --- | --- |
    | Feed | 07:00 |
    """

    assert [heading, paragraph, list, table] = RubyMarkdown.blocks(text)
    assert heading == "<h4>The day</h4>"
    assert paragraph == "<p>Five tasks are still open.</p>"
    assert list =~ "<li>Feed the goats</li>"
    assert table =~ ~s(<td data-label="Time">07:00</td>)
  end

  test "makes no image: an image is its words, and the browser fetches nothing" do
    html = RubyMarkdown.html("Here: ![the notes](https://example.org/p?d=notes)")

    assert html == "<p>Here: the notes</p>"
    refute html =~ "<img"
    refute html =~ "example.org"
  end

  test "makes no link: a link, an autolink and a reference link are their words" do
    html =
      RubyMarkdown.html("""
      See [the full list](https://example.org/more), <https://example.org/x> and [this][r].

      [r]: https://example.org/r
      """)

    refute html =~ "<a"
    refute html =~ "href"
    assert html =~ "See the full list, https://example.org/x and this."
    # A record that a tool returned is no link yet either.
    assert RubyMarkdown.html("[Biscuit](resident:0198c2)") == "<p>Biscuit</p>"
  end

  test "makes no raw HTML: a tag is text that the page shows" do
    html =
      RubyMarkdown.html("<script>alert(1)</script>\n\nA <b>bold</b> <img src=x onerror=y> word")

    refute html =~ "<script"
    refute html =~ "<b>"
    refute html =~ "<img"
    assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert html =~ "&lt;b&gt;bold&lt;/b&gt;"
  end

  test "closes what is open at the end, as the words arrive" do
    assert RubyMarkdown.blocks("A **bold") == ["<p>A <strong>bold</strong></p>"]

    assert RubyMarkdown.blocks("- one\n- [tw](http://exa") == [
             "<ul>\n<li>one</li>\n<li>tw</li>\n</ul>"
           ]
  end

  test "gives nothing for no text" do
    assert RubyMarkdown.blocks(nil) == []
    assert RubyMarkdown.blocks("") == []
  end

  test "puts a heading below the heading of its message, and writes no class" do
    assert RubyMarkdown.blocks("# Top\n\n### Low\n\n###### Six") ==
             ["<h3>Top</h3>", "<h5>Low</h5>", "<h6>Six</h6>"]

    html = RubyMarkdown.html("```elixir\nIO.puts(1)\n```")
    assert html =~ ~s(<pre lang="elixir">)
    refute html =~ "class="
  end

  test "names the column of each cell of a table, for a phone" do
    [table] =
      RubyMarkdown.blocks(
        "| Resident | Last \"weight\" |\n| --- | --- |\n| **Clover** | 985 g <b>x</b> |\n"
      )

    assert table =~ ~s(<th scope="col">Last &quot;weight&quot;</th>)
    assert table =~ "<td><strong>Clover</strong></td>"
    assert table =~ ~s(<td data-label="Last &quot;weight&quot;">985 g &lt;b&gt;x&lt;/b&gt;</td>)
  end
end
