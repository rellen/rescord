defmodule RescordWeb.SignInHTML do
  @moduledoc """
  The pages of the sign-in. The markup is classless (ADR 0004).
  """
  use RescordWeb, :html

  embed_templates "sign_in_html/*"
end
