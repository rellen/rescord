defmodule Rescord.Notifications.WebPush do
  @moduledoc """
  A message of Web Push, over `:crypto` alone (issue 29, ADR 0106):

    * `encrypt/4` encrypts the content for one device, as RFC 8291 says
      (`Content-Encoding: aes128gcm` of RFC 8188, one record). The push
      service cannot read it.
    * `vapid/4` makes the header `Authorization` of RFC 8292: a JWT that
      the private key of the server signs with ES256, and the public key.
    * `keys/0` makes a key pair of P-256 for the server.
    * `allowed_endpoint?/1` says whether an address that a browser gave is
      one of the push services that browsers use. Rescord sends to no other
      address: a browser must not make the server call a host of its choice.

  Each key and secret is the raw bytes: a public key is the uncompressed
  point of 65 bytes, a private key 32 bytes, the secret `auth` 16 bytes.
  Base64url is for the browser and the headers only.
  """

  @curve :prime256v1
  @record_size 4096

  # The push services of the browsers (issue 29, section 5): Google for
  # Chrome, Edge on other systems and Android, Mozilla for Firefox, Apple for
  # Safari, Microsoft for Edge on Windows.
  @exact_hosts ["fcm.googleapis.com", "android.googleapis.com"]
  @host_suffixes [".push.services.mozilla.com", ".push.apple.com", ".notify.windows.com"]

  @type key_pair :: %{public: <<_::520>>, private: <<_::256>>}

  @doc "A new key pair of P-256."
  @spec keys() :: key_pair
  def keys do
    {public, private} = :crypto.generate_key(:ecdh, @curve)
    %{public: public, private: pad(private)}
  end

  @doc "Base64url with no padding, as the browsers and RFC 8292 write a key."
  @spec encode(binary) :: String.t()
  def encode(bytes), do: Base.url_encode64(bytes, padding: false)

  @doc "Reads Base64url with or without padding."
  @spec decode(String.t()) :: {:ok, binary} | :error
  def decode(text) when is_binary(text),
    do: Base.url_decode64(String.trim_trailing(text, "="), padding: false)

  def decode(_other), do: :error

  @doc "Whether a public key of a device has the form of a point of P-256."
  @spec device_key?(binary) :: boolean
  def device_key?(<<4, _point::binary-size(64)>>), do: true
  def device_key?(_other), do: false

  @doc """
  Whether the address of a subscription is at a push service that Rescord
  sends to: HTTPS on the default port, with no user and a host of the list.
  """
  @spec allowed_endpoint?(String.t()) :: boolean
  def allowed_endpoint?(endpoint) when is_binary(endpoint) and byte_size(endpoint) <= 1_000 do
    case URI.new(endpoint) do
      {:ok, %URI{scheme: "https", host: host, port: 443, userinfo: nil}} when is_binary(host) ->
        host = String.downcase(host)
        host in @exact_hosts or Enum.any?(@host_suffixes, &String.ends_with?(host, &1))

      _other ->
        false
    end
  end

  def allowed_endpoint?(_endpoint), do: false

  @doc """
  Encrypts `plaintext` for the device with the public key `device_public`
  and the secret `auth`, as RFC 8291. Returns the body of the request.

  The options `:salt` and `:keys` (the key pair of this message) are for
  the test vectors of the RFC: each message gets new ones otherwise.
  """
  @spec encrypt(binary, binary, binary, keyword) :: binary
  def encrypt(plaintext, device_public, auth, opts \\ [])
      when byte_size(plaintext) <= @record_size - 17 do
    salt = Keyword.get_lazy(opts, :salt, fn -> :crypto.strong_rand_bytes(16) end)
    %{public: sender_public, private: sender_private} = Keyword.get_lazy(opts, :keys, &keys/0)

    ecdh_secret = :crypto.compute_key(:ecdh, device_public, sender_private, @curve)

    # The secret `auth` and the agreement give the key material (RFC 8291,
    # section 3.4), and RFC 8188 gives the key and the nonce from it.
    key_info = "WebPush: info" <> <<0>> <> device_public <> sender_public
    ikm = hkdf(auth, ecdh_secret, key_info, 32)
    cek = hkdf(salt, ikm, "Content-Encoding: aes128gcm" <> <<0>>, 16)
    nonce = hkdf(salt, ikm, "Content-Encoding: nonce" <> <<0>>, 12)

    # One record, the last: the delimiter 2 and no padding.
    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_128_gcm, cek, nonce, plaintext <> <<2>>, <<>>, true)

    header = salt <> <<@record_size::32, byte_size(sender_public)::8>> <> sender_public
    header <> ciphertext <> tag
  end

  @doc """
  The value of the header `Authorization` for a request to `endpoint`
  (RFC 8292): `vapid t=<JWT>, k=<public key>`. The token holds the origin
  of the push service, a time 12 hours ahead at most, and the contact of
  the server.
  """
  @spec vapid(String.t(), key_pair, String.t(), DateTime.t()) :: String.t()
  def vapid(endpoint, %{public: public, private: private}, contact, now) do
    %URI{scheme: scheme, host: host} = URI.parse(endpoint)

    header = encode(JSON.encode!(%{"typ" => "JWT", "alg" => "ES256"}))

    claims =
      encode(
        JSON.encode!(%{
          "aud" => "#{scheme}://#{host}",
          "exp" => DateTime.to_unix(now) + 12 * 60 * 60,
          "sub" => contact
        })
      )

    input = header <> "." <> claims
    der = :crypto.sign(:ecdsa, :sha256, input, [private, @curve])
    "vapid t=#{input}.#{encode(raw_signature(der))}, k=#{encode(public)}"
  end

  # HKDF of RFC 5869 for one block: what RFC 8291 writes out.
  defp hkdf(salt, ikm, info, length) do
    prk = :crypto.mac(:hmac, :sha256, salt, ikm)
    binary_part(:crypto.mac(:hmac, :sha256, prk, info <> <<1>>), 0, length)
  end

  # ES256 of JWS is r and s of 32 bytes each, where `:crypto` gives DER.
  defp raw_signature(der) do
    {:"ECDSA-Sig-Value", r, s} = :public_key.der_decode(:"ECDSA-Sig-Value", der)
    <<r::unsigned-big-256, s::unsigned-big-256>>
  end

  # `:crypto` can give a private key of fewer than 32 bytes.
  defp pad(private) when byte_size(private) < 32,
    do: :binary.copy(<<0>>, 32 - byte_size(private)) <> private

  defp pad(private), do: private
end
