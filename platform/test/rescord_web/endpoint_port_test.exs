defmodule RescordWeb.EndpointPortTest do
  @moduledoc """
  Holds the port of the server of the tests (ADR 0023).

  `config/runtime.exs` runs after `config/test.exs`. A line there that sets
  the port for each environment moves the tests to port 4000 with no error,
  and then `mix test` cannot start beside `mix phx.server`.
  """

  use ExUnit.Case, async: true

  test "the server of the tests listens on the port of config/test.exs" do
    assert RescordWeb.Endpoint.config(:http)[:port] == 4002
  end

  test "an address that the endpoint builds has the port that the server listens on" do
    assert URI.parse(RescordWeb.Endpoint.url()).port == RescordWeb.Endpoint.config(:http)[:port]
  end
end
