defmodule RescordWeb.SecurityHeadersTest do
  @moduledoc """
  Holds the headers of security of a page (ADR 0115): a strict
  `Content-Security-Policy`, and the headers of Phoenix beside it. A
  controller that sends a file keeps its own policy, a sandbox.

  The browser tests run each page under this policy, so a page that needs
  more than the policy gives shows there.
  """

  use RescordWeb.ConnCase, async: true

  alias RescordWeb.SecurityHeaders

  doctest SecurityHeaders

  test "a page has the policy, and the headers of Phoenix", %{conn: conn} do
    conn = get(conn, ~p"/sign-in")

    assert [policy] = get_resp_header(conn, "content-security-policy")
    assert policy == SecurityHeaders.content_security_policy()

    for directive <- [
          "default-src 'self'",
          "script-src 'self'",
          "style-src 'self'",
          "object-src 'none'",
          "form-action 'self'",
          "frame-ancestors 'self'"
        ] do
      assert policy =~ directive
    end

    refute policy =~ "unsafe-inline"
    refute policy =~ "unsafe-eval"

    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]
    assert [permissions] = get_resp_header(conn, "permissions-policy")
    assert permissions =~ "camera=()"
  end

  test "in production the session cookie goes over HTTPS only" do
    prod = Config.Reader.read!("config/prod.exs", env: :prod, target: :host)
    assert prod[:rescord][:secure_session_cookie] == true
  end

  test "the socket of LiveView is at the address of the endpoint" do
    assert SecurityHeaders.content_security_policy("http://localhost:4002") =~
             "connect-src 'self' ws://localhost:4002;"
  end
end
