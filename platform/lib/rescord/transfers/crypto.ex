defmodule Rescord.Transfers.Crypto do
  @moduledoc """
  The cryptography of a transfer file between two Rescord servers
  (ADR 0043), with `:crypto` of OTP and no other library.

  Each refuge has two key pairs (`keys/0`): an Ed25519 pair that signs,
  and an X25519 pair that receives encrypted files.

  ## A sealed file

  `seal/4` encrypts the payload for the refuge that receives it, and signs
  it as the refuge that sends it:

    1. It makes an X25519 key pair for this file alone, and agrees a secret
       with the public key of the receiver.
    2. The key of AES-256-GCM is the HMAC-SHA256 of that secret, with the
       two public keys in the message, so the key belongs to this file and
       this receiver.
    3. The header is JSON: the fields of the caller, the public key of this
       file, the nonce, and the SHA-256 of the encrypted payload. It is the
       additional data of the encryption, so a change to it breaks the
       decryption.
    4. The sender signs the exact bytes of the header with Ed25519. The
       header holds the hash of the payload, so the signature covers both.

  `open/5` checks the signature with the public key that the receiver
  recorded for the sender, then the hash, then decrypts. It returns one of
  three errors, and never a part of a payload that it did not check.

  ## Keys at rest

  `wrap/2` and `unwrap/2` keep a private key in the database encrypted
  with AES-256-GCM, under a key that the secret of the server gives
  (`Rescord.Transfers.Keys`).
  """

  @info "rescord-transfer-v1"
  @wrap_info "rescord-key-wrap-v1"

  @typedoc "The four keys of a refuge, each 32 bytes."
  @type keys :: %{
          sign_public: binary,
          sign_private: binary,
          box_public: binary,
          box_private: binary
        }

  @doc "Makes the two key pairs of a refuge."
  @spec keys() :: keys
  def keys do
    {sign_public, sign_private} = :crypto.generate_key(:eddsa, :ed25519)
    {box_public, box_private} = :crypto.generate_key(:ecdh, :x25519)

    %{
      sign_public: sign_public,
      sign_private: sign_private,
      box_public: box_public,
      box_private: box_private
    }
  end

  @doc """
  Encrypts `plaintext` for the receiver with the public key `box_public`,
  and signs it with `sign_private`. `fields` go into the header, which is
  not secret. Returns the bytes of the header, the signature and the
  encrypted payload.
  """
  @spec seal(binary, map, binary, binary) ::
          %{header: binary, signature: binary, payload: binary}
  def seal(plaintext, fields, sign_private, box_public) do
    {file_public, file_private} = :crypto.generate_key(:ecdh, :x25519)

    key =
      file_key(
        :crypto.compute_key(:ecdh, box_public, file_private, :x25519),
        file_public,
        box_public
      )

    nonce = :crypto.strong_rand_bytes(12)

    # The header names the hash of the payload, and the payload is
    # encrypted with the header as its additional data: the hash is of
    # the ciphertext, so it comes after the encryption. The additional
    # data is the header without the hash.
    base =
      Map.merge(fields, %{
        "file_key" => Base.encode64(file_public),
        "nonce" => Base.encode64(nonce)
      })

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, plaintext, aad(base), true)

    payload = ciphertext <> tag
    header = base |> Map.put("payload_sha256", sha256(payload)) |> Jason.encode!()
    signature = :crypto.sign(:eddsa, :none, header, [sign_private, :ed25519])

    %{header: header, signature: signature, payload: payload}
  end

  @doc """
  Checks and decrypts a sealed file. `sign_public` is the key that the
  receiver recorded for the sender, and `box_private` is the private key of
  the receiver.
  """
  @spec open(binary, binary, binary, binary, binary) ::
          {:ok, binary, map} | {:error, :signature | :payload | :decrypt}
  def open(header, signature, payload, sign_public, box_private) do
    with true <- verify?(header, signature, sign_public) || {:error, :signature},
         {:ok, fields} <- Jason.decode(header),
         true <- fields["payload_sha256"] == sha256(payload) || {:error, :payload},
         {:ok, file_public} <- decode(fields["file_key"]),
         {:ok, nonce} <- decode(fields["nonce"]),
         true <- byte_size(payload) > 16 || {:error, :payload} do
      {box_public, _private} = :crypto.generate_key(:ecdh, :x25519, box_private)
      shared = :crypto.compute_key(:ecdh, file_public, box_private, :x25519)
      key = file_key(shared, file_public, box_public)
      size = byte_size(payload) - 16
      <<ciphertext::binary-size(^size), tag::binary-size(16)>> = payload
      base = Map.delete(fields, "payload_sha256")

      case :crypto.crypto_one_time_aead(
             :aes_256_gcm,
             key,
             nonce,
             ciphertext,
             aad(base),
             tag,
             false
           ) do
        plaintext when is_binary(plaintext) -> {:ok, plaintext, fields}
        :error -> {:error, :decrypt}
      end
    else
      {:error, reason} when reason in [:signature, :payload, :decrypt] -> {:error, reason}
      _bad -> {:error, :payload}
    end
  rescue
    # A key of the wrong size, or a header that is no map.
    _error -> {:error, :payload}
  end

  @doc """
  The fingerprint of the public keys of a refuge: 32 hex digits in groups
  of four. Two administrators read it to each other, so that each knows
  that a partner card is the right one.
  """
  @spec fingerprint(binary, binary) :: String.t()
  def fingerprint(sign_public, box_public) do
    :crypto.hash(:sha256, sign_public <> box_public)
    |> binary_part(0, 16)
    |> Base.encode16()
    |> String.graphemes()
    |> Enum.chunk_every(4)
    |> Enum.map_join(" ", &Enum.join/1)
  end

  @doc "Encrypts a private key with the secret of the server."
  @spec wrap(binary, binary) :: binary
  def wrap(private_key, secret) do
    nonce = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(
        :aes_256_gcm,
        wrap_key(secret),
        nonce,
        private_key,
        @wrap_info,
        true
      )

    nonce <> tag <> ciphertext
  end

  @doc "Decrypts a private key that `wrap/2` encrypted, or returns `:error`."
  @spec unwrap(binary, binary) :: {:ok, binary} | :error
  def unwrap(<<nonce::binary-size(12), tag::binary-size(16), ciphertext::binary>>, secret) do
    case :crypto.crypto_one_time_aead(
           :aes_256_gcm,
           wrap_key(secret),
           nonce,
           ciphertext,
           @wrap_info,
           tag,
           false
         ) do
      key when is_binary(key) -> {:ok, key}
      :error -> :error
    end
  end

  def unwrap(_other, _secret), do: :error

  defp file_key(shared, file_public, box_public),
    do: :crypto.mac(:hmac, :sha256, shared, @info <> file_public <> box_public)

  defp wrap_key(secret), do: :crypto.mac(:hmac, :sha256, secret, @wrap_info)

  defp verify?(header, signature, sign_public)
       when is_binary(header) and is_binary(signature) and byte_size(sign_public) == 32 do
    :crypto.verify(:eddsa, :none, header, signature, [sign_public, :ed25519])
  end

  defp verify?(_header, _signature, _key), do: false

  # The additional data: the header without the hash, one line for each
  # field in the order of the keys, so the sender and the receiver make the
  # same bytes.
  defp aad(fields),
    do:
      fields
      |> Enum.sort()
      |> Enum.map_join("\n", fn {key, value} -> "#{key}=#{Jason.encode!(value)}" end)

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp decode(text) when is_binary(text), do: Base.decode64(text)
  defp decode(_other), do: :error
end
