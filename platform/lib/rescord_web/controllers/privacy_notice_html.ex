defmodule RescordWeb.PrivacyNoticeHTML do
  @moduledoc "The pages of the privacy notices (`RescordWeb.PrivacyNoticeController`)."

  use RescordWeb, :html

  embed_templates "privacy_notice_html/*"

  @doc "The paragraphs of words that an organisation added, one for each blank line."
  @spec paragraphs(String.t() | nil) :: [String.t()]
  def paragraphs(nil), do: []

  def paragraphs(text),
    do: text |> String.split(~r/\R\s*\R/) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
end
