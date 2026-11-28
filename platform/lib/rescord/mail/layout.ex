defmodule Rescord.Mail.Layout do
  @moduledoc """
  The layout of each email, in `layout.mjml.eex`: the head, the mark and
  the name, the card that holds the content of one email, and the note
  below it. It reads `@subject`, `@preview` and `@note`.
  """

  use MjmlEEx.Layout, mjml_layout: "layout.mjml.eex"
end
