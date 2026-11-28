defmodule RescordWeb.ClientAddress do
  @moduledoc """
  Finds the address of the client behind a reverse proxy (ADR 0046), and
  puts it in `conn.remote_ip`. The limits of the sign-in count it.

  A reverse proxy in front of Rescord connects from its own address, so
  each client would have the address of the proxy. A proxy that Rescord
  trusts says the address of the client in `X-Forwarded-For`, and adds it
  at the end of the addresses that are there.

  When the connection comes from a trusted proxy, the plug reads the
  addresses of `X-Forwarded-For` from the right, and takes the first one
  that is not a trusted proxy. A client can write any address at the left
  of the header, and a trusted proxy can only add to the right, so the
  client cannot choose the address that Rescord counts. An entry that is
  not an address stops the search at the last trusted one. A connection
  from another address keeps its own address, and its header is ignored.

  The trusted proxies come from `RESCORD_TRUSTED_PROXIES` in production,
  as addresses and networks: `127.0.0.0/8, ::1` by default, a proxy on the
  same machine. An IPv4 address that a socket of IPv6 gives as
  `::ffff:a.b.c.d` becomes `a.b.c.d`.
  """

  @behaviour Plug

  import Bitwise

  @typedoc "An address and the number of bits of its network."
  @type network :: {:inet.ip_address(), non_neg_integer}

  @default "127.0.0.0/8, ::1"

  @doc """
  The networks of a text of addresses and networks, separated by commas,
  or the first entry that is neither.

      iex> RescordWeb.ClientAddress.parse_networks("10.0.0.0/8, ::1")
      {:ok, [{{10, 0, 0, 0}, 8}, {{0, 0, 0, 0, 0, 0, 0, 1}, 128}]}

      iex> RescordWeb.ClientAddress.parse_networks("10.0.0.0/33")
      {:error, "10.0.0.0/33"}
  """
  @spec parse_networks(String.t()) :: {:ok, [network]} | {:error, String.t()}
  def parse_networks(text) do
    text
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, networks} ->
      case parse_network(entry) do
        {:ok, network} -> {:cont, {:ok, [network | networks]}}
        :error -> {:halt, {:error, entry}}
      end
    end)
    |> case do
      {:ok, networks} -> {:ok, Enum.reverse(networks)}
      error -> error
    end
  end

  @doc """
  The part of the address of a client that a rate limit counts (ADR 0115):
  an IPv4 address whole, and the network of 64 bits of an IPv6 address. A
  single home or server gets a whole /64 of IPv6, so a count of each address
  would give one client a new limit for each address of its network.

      iex> RescordWeb.ClientAddress.limit_key({192, 0, 2, 7})
      "192.0.2.7"

      iex> RescordWeb.ClientAddress.limit_key({0x2001, 0xDB8, 1, 2, 3, 4, 5, 6})
      "2001:db8:1:2::/64"
  """
  @spec limit_key(:inet.ip_address()) :: String.t()
  def limit_key({_, _, _, _} = address), do: address |> :inet.ntoa() |> to_string()

  def limit_key({a, b, c, d, _, _, _, _}),
    do: to_string(:inet.ntoa({a, b, c, d, 0, 0, 0, 0})) <> "/64"

  @doc "The trusted networks of the configuration, or of the default."
  @spec trusted() :: [network]
  def trusted do
    case Application.get_env(:rescord, __MODULE__, [])[:trusted] do
      nil ->
        {:ok, networks} = parse_networks(@default)
        networks

      networks ->
        networks
    end
  end

  @impl true
  def init(options), do: options

  @impl true
  def call(conn, _options) do
    peer = normalise(conn.remote_ip)
    trusted = trusted()

    if trusted?(peer, trusted) do
      forwarded =
        conn
        |> Plug.Conn.get_req_header("x-forwarded-for")
        |> Enum.flat_map(&String.split(&1, ","))
        |> Enum.map(&String.trim/1)
        |> Enum.reverse()

      %{conn | remote_ip: client(peer, forwarded, trusted)}
    else
      %{conn | remote_ip: peer}
    end
  end

  # The entries of the header, from the right.
  defp client(current, [], _trusted), do: current

  defp client(current, [entry | rest], trusted) do
    case parse_address(entry) do
      {:ok, address} ->
        if trusted?(address, trusted), do: client(address, rest, trusted), else: address

      :error ->
        current
    end
  end

  defp trusted?(address, networks), do: Enum.any?(networks, &member?(address, &1))

  defp member?(address, {network, bits}) when tuple_size(address) == tuple_size(network) do
    shift = width(address) - bits
    to_integer(address) >>> shift == to_integer(network) >>> shift
  end

  defp member?(_address, _network), do: false

  defp parse_network(entry) do
    {text, bits} =
      case String.split(entry, "/", parts: 2) do
        [text] -> {text, nil}
        [text, bits] -> {text, bits}
      end

    with {:ok, address} <- parse_address(text),
         {:ok, bits} <- parse_bits(bits, width(address)) do
      {:ok, {address, bits}}
    end
  end

  defp parse_bits(nil, width), do: {:ok, width}

  defp parse_bits(text, width) do
    case Integer.parse(text) do
      {bits, ""} when bits in 0..width//1 -> {:ok, bits}
      _other -> :error
    end
  end

  defp parse_address(text) do
    case :inet.parse_strict_address(String.to_charlist(text)) do
      {:ok, address} -> {:ok, normalise(address)}
      {:error, _reason} -> :error
    end
  end

  defp normalise({0, 0, 0, 0, 0, 0xFFFF, high, low}),
    do: {high >>> 8, high &&& 0xFF, low >>> 8, low &&& 0xFF}

  defp normalise(address), do: address

  defp width(address) when tuple_size(address) == 4, do: 32
  defp width(_address), do: 128

  defp to_integer(address) do
    step = if tuple_size(address) == 4, do: 8, else: 16
    address |> Tuple.to_list() |> Enum.reduce(0, &((&2 <<< step) + &1))
  end
end
