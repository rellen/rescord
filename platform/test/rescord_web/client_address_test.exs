defmodule RescordWeb.ClientAddressTest do
  @moduledoc """
  Holds the address of a client behind a reverse proxy (ADR 0046): a
  trusted proxy says it in `X-Forwarded-For`, the plug reads the header from
  the right, and a client cannot choose the address that Rescord counts.

  The tests change the configuration of the application, so they do not
  run beside others.
  """

  use ExUnit.Case, async: false

  import Plug.Test, only: [conn: 2]

  alias RescordWeb.ClientAddress

  doctest ClientAddress

  setup do
    {:ok, trusted} = ClientAddress.parse_networks("127.0.0.1/8, ::1, 10.0.0.0/8, 2001:db8::/32")
    Shoddy.Tests.put_app_env(:rescord, ClientAddress, trusted: trusted)
  end

  defp client(peer, forwarded \\ []) do
    conn = %{conn(:get, "/") | remote_ip: peer}

    forwarded
    |> Enum.reduce(conn, fn value, conn ->
      %{conn | req_headers: conn.req_headers ++ [{"x-forwarded-for", value}]}
    end)
    |> ClientAddress.call([])
    |> Map.fetch!(:remote_ip)
  end

  test "a connection that no proxy forwards keeps its address, and its header is ignored" do
    assert client({198, 51, 100, 1}) == {198, 51, 100, 1}
    assert client({198, 51, 100, 1}, ["203.0.113.7"]) == {198, 51, 100, 1}
  end

  test "a trusted proxy says the address of the client" do
    assert client({127, 0, 0, 1}, ["203.0.113.7"]) == {203, 0, 113, 7}
    assert client({0, 0, 0, 0, 0, 0, 0, 1}, ["203.0.113.7"]) == {203, 0, 113, 7}
  end

  test "a client cannot choose its address by writing the header" do
    # The client wrote the first address; the proxy added the second.
    assert client({127, 0, 0, 1}, ["198.51.100.1, 203.0.113.7"]) == {203, 0, 113, 7}
    assert client({127, 0, 0, 1}, ["198.51.100.1", "203.0.113.7"]) == {203, 0, 113, 7}
  end

  test "the search passes over each trusted proxy of a chain" do
    assert client({127, 0, 0, 1}, ["203.0.113.7, 10.0.0.5, 10.1.2.3"]) == {203, 0, 113, 7}
    # When each address is a trusted proxy, the first is the client.
    assert client({127, 0, 0, 1}, ["10.0.0.9"]) == {10, 0, 0, 9}
  end

  test "an entry that is not an address stops the search at the last trusted one" do
    assert client({127, 0, 0, 1}, ["203.0.113.7, nonsense"]) == {127, 0, 0, 1}
    assert client({127, 0, 0, 1}, ["203.0.113.7, 10.0.0.5, 203.0.113.7:443"]) == {127, 0, 0, 1}
    assert client({127, 0, 0, 1}, ["nonsense, 10.0.0.5"]) == {10, 0, 0, 5}
    assert client({127, 0, 0, 1}, [""]) == {127, 0, 0, 1}
  end

  test "an address of IPv6 is a client or a proxy as its network says" do
    assert client({0x2001, 0xDB8, 0, 0, 0, 0, 0, 5}, ["2001:db9::7"]) ==
             {0x2001, 0xDB9, 0, 0, 0, 0, 0, 7}

    assert client({0x2001, 0xDB9, 0, 0, 0, 0, 0, 5}, ["203.0.113.7"]) ==
             {0x2001, 0xDB9, 0, 0, 0, 0, 0, 5}
  end

  test "an IPv4 address that a socket of IPv6 gives becomes an IPv4 address" do
    mapped_loopback = {0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 0x0001}
    assert client(mapped_loopback, ["203.0.113.7"]) == {203, 0, 113, 7}
    assert client({0, 0, 0, 0, 0, 0xFFFF, 0xC633, 0x6401}) == {198, 51, 100, 1}
    assert client({127, 0, 0, 1}, ["::ffff:203.0.113.7"]) == {203, 0, 113, 7}
  end

  test "a text of networks gives each network, or the first entry that is not one" do
    assert ClientAddress.parse_networks(" 192.168.0.0/16 ,, 203.0.113.7 ") ==
             {:ok, [{{192, 168, 0, 0}, 16}, {{203, 0, 113, 7}, 32}]}

    for bad <- ["nonsense", "10.0.0.0/x", "10.0.0.0/", "::1/129", "10.0.0.0/8/8", "10.1"] do
      assert ClientAddress.parse_networks("127.0.0.1, " <> bad) == {:error, bad}
    end
  end

  test "with no configuration, a proxy on the same machine is trusted" do
    Application.delete_env(:rescord, ClientAddress)

    assert client({127, 0, 0, 1}, ["203.0.113.7"]) == {203, 0, 113, 7}
    assert client({10, 0, 0, 5}, ["203.0.113.7"]) == {10, 0, 0, 5}
  end
end
