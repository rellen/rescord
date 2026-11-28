defmodule RescordWeb.SecurityHeaders do
  @moduledoc """
  The headers of security of each page (ADR 0115): the headers of
  `Phoenix.Controller.put_secure_browser_headers/2`, a strict
  `Content-Security-Policy`, and a `Permissions-Policy`.

  The markup of Rescord has no inline script, no inline style and no `style`
  attribute, and each script, stylesheet, font and image comes from the
  site. The policy therefore lets a page load only files of the site. A
  page that writes HTML of its own (`RescordWeb.Markdown`,
  `RescordWeb.RubyMarkdown`) escapes the words of people already; the
  policy is a second wall behind that: a script or an image of another
  site that got into a page does not run or load.

    * `img-src` has `data:` for the small drawings in the stylesheet.
    * `connect-src` names the socket of LiveView at the address of the
      endpoint, because an older browser does not take `ws:` and `wss:` as
      `'self'`.
    * `form-action 'self'`: a form sends only to the site.

  A controller that sends a file sets a stricter policy of its own (a
  sandbox), which takes the place of this one.

  ## Oban Web

  Oban Web at `/root/oban` (ADR 0110) is the page of a package, with an
  inline script and `style` attributes. Its routes take this plug again
  with `oban: true`: a new nonce for each response, in `conn.assigns`
  under `:csp_nonce`, which Oban Web puts on its script and its stylesheet
  (`csp_nonce_assign_key`), and `style-src-attr 'unsafe-inline'` for the
  widths of its bars. Only a root user opens those routes.
  """

  @behaviour Plug

  @permissions "camera=(), microphone=(), geolocation=(), payment=(), usb=()"

  @impl true
  def init(options), do: options

  @impl true
  def call(conn, options) do
    {conn, extra} =
      if Keyword.get(options, :oban, false) do
        nonce = 18 |> :crypto.strong_rand_bytes() |> Base.encode64()
        {Plug.Conn.assign(conn, :csp_nonce, nonce), [nonce: nonce, style_attributes: true]}
      else
        {conn, []}
      end

    Phoenix.Controller.put_secure_browser_headers(conn, %{
      "content-security-policy" => content_security_policy(RescordWeb.Endpoint.url(), extra),
      "permissions-policy" => @permissions
    })
  end

  @doc """
  The `Content-Security-Policy` of a page, for the endpoint at `url`.
  `nonce:` lets a script and a stylesheet with that nonce in, and
  `style_attributes: true` lets `style` attributes in.

      iex> RescordWeb.SecurityHeaders.content_security_policy("https://rescord.example.org")
      "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; " <>
        "font-src 'self'; connect-src 'self' wss://rescord.example.org; " <>
        "manifest-src 'self'; worker-src 'self'; object-src 'none'; base-uri 'self'; " <>
        "form-action 'self'; frame-ancestors 'self'"

      iex> RescordWeb.SecurityHeaders.content_security_policy("http://localhost:4000",
      ...>   nonce: "abc", style_attributes: true)
      "default-src 'self'; script-src 'self' 'nonce-abc'; style-src 'self' 'nonce-abc'; " <>
        "style-src-attr 'unsafe-inline'; img-src 'self' data:; font-src 'self'; " <>
        "connect-src 'self' ws://localhost:4000; manifest-src 'self'; worker-src 'self'; " <>
        "object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'self'"
  """
  @spec content_security_policy(String.t(), keyword) :: String.t()
  def content_security_policy(url \\ RescordWeb.Endpoint.url(), options \\ []) do
    nonce = if options[:nonce], do: " 'nonce-#{options[:nonce]}'", else: ""
    attributes = if options[:style_attributes], do: ["style-src-attr 'unsafe-inline'"], else: []

    Enum.join(
      ["default-src 'self'", "script-src 'self'#{nonce}", "style-src 'self'#{nonce}"] ++
        attributes ++
        [
          "img-src 'self' data:",
          "font-src 'self'",
          "connect-src 'self' #{socket(url)}",
          "manifest-src 'self'",
          "worker-src 'self'",
          "object-src 'none'",
          "base-uri 'self'",
          "form-action 'self'",
          "frame-ancestors 'self'"
        ],
      "; "
    )
  end

  defp socket("https://" <> rest), do: "wss://" <> rest
  defp socket("http://" <> rest), do: "ws://" <> rest
end
