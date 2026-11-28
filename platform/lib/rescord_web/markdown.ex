defmodule RescordWeb.Markdown do
  @moduledoc """
  The words of a comment as HTML: a small part of Markdown (issue 29,
  ADR 0106). Rob chose it on 28 November 2026.

  A person types:

    * `**bold**` and `*italics*` (or `_italics_`);
    * a list, each line with `-`, `*` or `1.`;
    * a link, `[words](https://…)`, or an address alone, which is a link
      too: only `https:`, `http:` and `mailto:` make a link;
    * an empty line between paragraphs, and a new line in a paragraph.

  Each other thing of Markdown is text: a heading is a paragraph, code is
  its letters, a picture is its words. HTML that a person types is text,
  never markup.

  `MDEx` parses the words into a tree, and this module writes the HTML of
  the tree itself, node by node, from a short list of elements. It never
  asks the parser for HTML, so no option of the parser can let markup
  through: each text is escaped here, and a node that the list does not
  know gives its text alone.
  """

  use Phoenix.Component

  import Phoenix.HTML, only: [html_escape: 1, attributes_escape: 1]

  @schemes ~w(https http mailto)

  @doc "A comment in its HTML, in a `div` with `data-markdown`."
  attr :text, :string, required: true
  attr :rest, :global

  def markdown(assigns) do
    ~H"""
    <div data-markdown {@rest}>{to_html(@text)}</div>
    """
  end

  @doc """
  The HTML of `text`, safe for a page.

      iex> RescordWeb.Markdown.to_html("**Hi** <b>x</b>") |> Phoenix.HTML.safe_to_string()
      "<p><strong>Hi</strong> &lt;b&gt;x&lt;/b&gt;</p>"
  """
  @spec to_html(String.t() | nil) :: Phoenix.HTML.safe()
  def to_html(nil), do: {:safe, []}

  def to_html(text) when is_binary(text) do
    case MDEx.parse_document(text, extension: [autolink: true]) do
      {:ok, %MDEx.Document{nodes: nodes}} -> {:safe, blocks(nodes)}
      {:error, _error} -> {:safe, plain(text)}
    end
  end

  # The parser failed: each paragraph as text.
  defp plain(text) do
    for part <- String.split(text, ~r/\n\s*\n/, trim: true) do
      ["<p>", lines(part), "</p>"]
    end
  end

  ## Blocks

  defp blocks(nodes), do: Enum.map(nodes, &block/1)

  defp block(%MDEx.Paragraph{nodes: nodes}), do: ["<p>", inlines(nodes), "</p>"]

  defp block(%MDEx.List{list_type: :ordered, start: start} = list) do
    start = if is_integer(start) and start != 1, do: attributes(start: start), else: []
    ["<ol", start, ">", items(list), "</ol>"]
  end

  defp block(%MDEx.List{} = list), do: ["<ul>", items(list), "</ul>"]

  # A heading, code and HTML that a person typed are text.
  defp block(%MDEx.Heading{nodes: nodes}), do: ["<p>", inlines(nodes), "</p>"]
  defp block(%{literal: literal}) when is_binary(literal), do: ["<p>", lines(literal), "</p>"]
  defp block(%MDEx.ThematicBreak{}), do: []

  # A quote, and any other block of blocks: its blocks.
  defp block(%{nodes: nodes}) when is_list(nodes), do: blocks(nodes)
  defp block(_other), do: []

  defp items(%MDEx.List{nodes: nodes, tight: tight}) do
    for item <- nodes, do: ["<li>", item_body(item, tight), "</li>"]
  end

  # A tight list has no paragraph in an item.
  defp item_body(%{nodes: nodes}, true) do
    Enum.map(nodes, fn
      %MDEx.Paragraph{nodes: inline} -> inlines(inline)
      other -> block(other)
    end)
  end

  defp item_body(%{nodes: nodes}, _loose), do: blocks(nodes)

  ## Inlines

  defp inlines(nodes), do: Enum.map(nodes, &inline/1)

  defp inline(%MDEx.Text{literal: literal}), do: escape(literal)
  defp inline(%MDEx.Strong{nodes: nodes}), do: ["<strong>", inlines(nodes), "</strong>"]
  defp inline(%MDEx.Emph{nodes: nodes}), do: ["<em>", inlines(nodes), "</em>"]
  # A new line in a paragraph is a new line on the page, as a person who
  # types a comment means it.
  defp inline(%MDEx.SoftBreak{}), do: "<br>"
  defp inline(%MDEx.LineBreak{}), do: "<br>"

  defp inline(%MDEx.Link{url: url, nodes: nodes}) do
    if link?(url) do
      href = attributes(href: url, rel: "nofollow noreferrer")
      ["<a", href, ">", inlines(nodes), "</a>"]
    else
      inlines(nodes)
    end
  end

  # Code and HTML that a person typed are text; a picture is its words.
  defp inline(%{literal: literal}) when is_binary(literal), do: escape(literal)
  defp inline(%{nodes: nodes}) when is_list(nodes), do: inlines(nodes)
  defp inline(_other), do: []

  defp lines(text),
    do:
      text
      |> String.trim_trailing("\n")
      |> String.split("\n")
      |> Enum.map(&escape/1)
      |> Enum.intersperse("<br>")

  defp attributes(list), do: list |> attributes_escape() |> Phoenix.HTML.safe_to_string()

  defp escape(text), do: text |> html_escape() |> Phoenix.HTML.safe_to_string()

  @doc """
  Whether `url` may be the address of a link: an address with the scheme
  `https:`, `http:` or `mailto:`, and no space or control character.
  """
  @spec link?(String.t()) :: boolean
  def link?(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme}} when is_binary(scheme) ->
        String.downcase(scheme) in @schemes and not String.match?(url, ~r/[\s\x00-\x1f\x7f]/u)

      _other ->
        false
    end
  end

  def link?(_url), do: false
end
