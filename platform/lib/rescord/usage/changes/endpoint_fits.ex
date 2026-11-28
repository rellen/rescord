defmodule Rescord.Usage.Changes.EndpointFits do
  @moduledoc """
  Holds the address of the usage counts to its rules (ADR 0098), and puts
  each problem on its field:

  - the mode `send` needs an address;
  - an address is `https://` or `http://`, with a host, and with no user
    or password in it;
  - a token goes only to an address with `https://`, or to this machine
    (`localhost`, `127.0.0.1`, `::1`), so that nobody on the way reads it.

  It reads the token as the argument that AshCloak has not yet encrypted,
  and a stored token through `token_set_at`. It decrypts nothing.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    mode = Ash.Changeset.get_attribute(changeset, :mode)
    endpoint = Ash.Changeset.get_attribute(changeset, :endpoint)

    token? =
      is_binary(Ash.Changeset.get_argument(changeset, :token)) or
        Ash.Changeset.get_attribute(changeset, :token_set_at) != nil

    case problem(mode, endpoint, token?) do
      nil ->
        :ok

      words ->
        {:error, Ash.Error.Changes.InvalidAttribute.exception(field: :endpoint, message: words)}
    end
  end

  @doc "The problem of an address, as words, or `nil`."
  @spec problem(atom, String.t() | nil, boolean) :: String.t() | nil
  def problem(:send, nil, _token?), do: "give the address that gets the counts"
  def problem(_mode, nil, _token?), do: nil

  def problem(_mode, endpoint, token?) do
    case URI.new(endpoint) do
      {:ok, %URI{scheme: scheme, host: host, userinfo: nil}}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        if token? and scheme == "http" and not loopback?(host),
          do: "a token goes only to an address with https://, or to this machine",
          else: nil

      {:ok, %URI{userinfo: userinfo}} when is_binary(userinfo) ->
        "put no user or password in the address: give a token"

      _other ->
        "give an address that starts with https://"
    end
  end

  @doc "Whether a host is this machine."
  @spec loopback?(String.t()) :: boolean
  def loopback?(host), do: host in ["localhost", "127.0.0.1", "::1", "[::1]"]
end
