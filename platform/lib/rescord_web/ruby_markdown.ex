defmodule RescordWeb.RubyMarkdown do
  @moduledoc """
  The words of Ruby as safe HTML, in blocks (ADR 0069).

  A reply is Markdown that a model wrote, and a record that the model read
  can hold text that tries to steer it. So the HTML that this module gives
  holds what the words say, and nothing that makes the browser act:

    * **no image**: an image makes the browser fetch its address, and an
      address can carry data out. An image becomes its words;
    * **no link**: a link becomes its words. Only a reference to a
      record that a tool returned in the conversation is to become a link
      to its page (ADR 0069);
    * **no raw HTML**: a tag is text that the page shows, escaped.
    * **no class**: a block of code names its language in `lang`, as the
      markup of Rescord has no class (ADR 0004).

  A heading of Ruby is an `h3` at the most, below the `h2` of its
  message, so the headings of a page keep their order. A table has a
  `data-label` on each cell with the words of its column, so it is a list
  of cards on a phone, as each table of Rescord is (ADR 0061).

  Each block of the text (a paragraph, a list, a table, a heading) is one
  string of HTML, so a page draws each block with a key, and LiveView sends
  only the block that changed while the words arrive. Markdown that is
  still open at the end, such as `**bold` with no end, is closed.
  """

  @options [
    extension: [table: true, strikethrough: true],
    auto_close: [links: :text, images: :text],
    render: [github_pre_lang: true]
  ]

  @doc "The blocks of a text, each as safe HTML. A text that is no Markdown gives its words."
  @spec blocks(String.t() | nil) :: [String.t()]
  def blocks(text) when is_binary(text) and text != "" do
    case MDEx.parse_document(text, @options) do
      {:ok, document} ->
        document
        |> MDEx.Document.update_nodes(&rewrite?/1, &rewrite/1)
        |> Map.fetch!(:nodes)
        |> Enum.map(&block_html/1)
        |> Enum.reject(&(&1 == ""))

      {:error, _error} ->
        [paragraph(text)]
    end
  end

  def blocks(_none), do: []

  @doc "The whole text as one string of safe HTML."
  @spec html(String.t() | nil) :: String.t()
  def html(text), do: text |> blocks() |> Enum.join("\n")

  # What the text must not hold as it is: a link, an image and HTML become
  # words, and a heading moves below the heading of its message.
  defp rewrite?(%MDEx.Link{}), do: true
  defp rewrite?(%MDEx.Image{}), do: true
  defp rewrite?(%MDEx.HtmlInline{}), do: true
  defp rewrite?(%MDEx.HtmlBlock{}), do: true
  defp rewrite?(%MDEx.Heading{}), do: true
  defp rewrite?(_node), do: false

  defp rewrite(%MDEx.HtmlBlock{literal: literal}),
    do: %MDEx.Paragraph{nodes: [%MDEx.Text{literal: String.trim_trailing(literal)}]}

  defp rewrite(%MDEx.Heading{level: level} = heading),
    do: %{heading | level: min(level + 2, 6)}

  defp rewrite(%MDEx.HtmlInline{literal: literal}), do: %MDEx.Text{literal: literal}
  defp rewrite(%{nodes: nodes}), do: %MDEx.Text{literal: words(nodes)}

  # The plain words of the nodes inside a link or an image.
  defp words(nodes) when is_list(nodes), do: Enum.map_join(nodes, &words/1)
  defp words(%{literal: literal}) when is_binary(literal), do: literal
  defp words(%{nodes: nodes}), do: words(nodes)
  defp words(_node), do: ""

  # A table is drawn here, so that each cell of the body names its column
  # in `data-label`, which the stylesheet shows on a phone.
  defp block_html(%MDEx.Table{nodes: [%MDEx.TableRow{nodes: head} | rows]}) do
    labels = Enum.map(head, &escape(words(&1.nodes)))

    header = Enum.map_join(head, &"<th scope=\"col\">#{inline(&1.nodes)}</th>")

    body =
      Enum.map_join(rows, fn %MDEx.TableRow{nodes: cells} ->
        row =
          cells
          |> Enum.with_index()
          |> Enum.map_join(fn
            {cell, 0} ->
              "<td>#{inline(cell.nodes)}</td>"

            {cell, index} ->
              ~s(<td data-label="#{Enum.at(labels, index, "")}">#{inline(cell.nodes)}</td>)
          end)

        "<tr>" <> row <> "</tr>"
      end)

    "<table><thead><tr>" <> header <> "</tr></thead><tbody>" <> body <> "</tbody></table>"
  end

  defp block_html(node) do
    %MDEx.Document{nodes: [node]}
    |> MDEx.to_html!(@options)
    |> String.trim()
  end

  # The inline nodes of a cell as safe HTML, with no paragraph around them.
  defp inline(nodes) do
    %MDEx.Paragraph{nodes: nodes}
    |> block_html()
    |> String.replace_prefix("<p>", "")
    |> String.replace_suffix("</p>", "")
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp paragraph(text), do: "<p>" <> escape(text) <> "</p>"
end
