defmodule RescordWeb.MarkdownTest do
  @moduledoc """
  The small part of Markdown of a comment (issue 29, ADR 0106): what it
  writes, and that no markup and no other kind of link gets through.
  """

  use ExUnit.Case, async: true

  alias RescordWeb.Markdown

  defp html(text), do: text |> Markdown.to_html() |> Phoenix.HTML.safe_to_string()

  test "writes bold, italics, paragraphs and new lines" do
    assert html("**Hazel** ate *all* of it") ==
             "<p><strong>Hazel</strong> ate <em>all</em> of it</p>"

    assert html("_one_\n\nTwo\nthree") == "<p><em>one</em></p><p>Two<br>three</p>"
  end

  test "writes a list with bullets and a numbered list, with its first number" do
    assert html("- one\n- two") == "<ul><li>one</li><li>two</li></ul>"
    assert html("1. one\n2. two") == "<ol><li>one</li><li>two</li></ol>"
    assert html("3. three\n4. four") == ~s(<ol start="3"><li>three</li><li>four</li></ol>)
  end

  test "writes a link to https, http and mailto, and an address alone as a link" do
    assert html("[the vet](https://vet.example.org/a?b=1&c=2)") ==
             ~s(<p><a href="https://vet.example.org/a?b=1&amp;c=2" rel="nofollow noreferrer">the vet</a></p>)

    assert html("see http://example.org") =~
             ~s(<a href="http://example.org" rel="nofollow noreferrer">http://example.org</a>)

    assert html("[mail](mailto:a@example.org)") =~ ~s(<a href="mailto:a@example.org")
  end

  test "keeps the words of a link with any other scheme, with no link" do
    for url <- [
          "javascript:alert(1)",
          "JaVaScRiPt:alert(1)",
          "data:text/html,hi",
          "vbscript:x",
          "/o/wattle/residents"
        ] do
      assert html("[words](#{url})") == "<p>words</p>", url
    end
  end

  test "writes HTML that a person types as text" do
    assert html("<script>alert(1)</script>") == "<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>"
    assert html("a <b onclick=x>b</b>") == "<p>a &lt;b onclick=x&gt;b&lt;/b&gt;</p>"
    assert html(~s|<img src=x onerror="alert(1)">|) =~ "&lt;img"
    refute html(~s|[x](https://e.org" onmouseover="alert(1))|) =~ ~s|" onmouseover|
  end

  test "writes a heading, code and a picture as their text" do
    assert html("# Heading") == "<p>Heading</p>"
    assert html("`code <i>`") == "<p>code &lt;i&gt;</p>"
    assert html("```\nline <b>\n```") == "<p>line &lt;b&gt;</p>"
    assert html("![a picture](https://e.org/p.png)") == "<p>a picture</p>"
  end

  test "writes a quote as its paragraphs" do
    assert html("> quoted **q**") == "<p>quoted <strong>q</strong></p>"
  end

  test "link?/1 takes only https, http and mailto with no space" do
    assert Markdown.link?("https://example.org")
    assert Markdown.link?("HTTPS://example.org")
    refute Markdown.link?("https://example.org/a b")
    refute Markdown.link?("java\tscript:alert(1)")
    refute Markdown.link?("ftp://example.org")
    refute Markdown.link?(nil)
  end
end
