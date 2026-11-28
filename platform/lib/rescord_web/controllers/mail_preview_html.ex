defmodule RescordWeb.MailPreviewHTML do
  @moduledoc """
  The list of the emails, for a developer (ADR 0070). The markup is
  classless (ADR 0004).
  """
  use RescordWeb, :html

  embed_templates "mail_preview_html/*"
end
