defmodule RescordWeb.EndpointPortTest do
  @moduledoc """
  Holds the port of the server of the tests (ADR 0023).

  `config/runtime.exs` runs after `config/test.exs`. A line there that sets
  the port for each environment moves the tests to port 4000 with no error,
  and then `mix test` cannot start beside `mix phx.server`. The slot k of
  scripts/test-in-parts.sh (RESCORD_TEST_SLOT), or else the part k of
  `mix test --partitions` (MIX_TEST_PARTITION), takes the port 4002 + k, so
  that several runs go side by side (ADR 0103).
  """

  use ExUnit.Case, async: true

  test "the server of the tests listens on the port of config/test.exs" do
    slot = System.get_env("RESCORD_TEST_SLOT") || System.get_env("MIX_TEST_PARTITION", "")
    offset = if slot == "", do: 0, else: String.to_integer(slot)

    assert RescordWeb.Endpoint.config(:http)[:port] == 4002 + offset
  end

  test "an address that the endpoint builds has the port that the server listens on" do
    assert URI.parse(RescordWeb.Endpoint.url()).port == RescordWeb.Endpoint.config(:http)[:port]
  end
end
