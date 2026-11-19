defmodule Rescord.Transfers.CryptoTest do
  @moduledoc """
  Holds the cryptography of a transfer file (ADR 0043): a sealed file
  opens only for its receiver and only with the key of its sender, and a
  change to any part of it is refused.
  """

  use ExUnit.Case, async: true

  alias Rescord.Transfers.Crypto

  setup do
    {:ok, sender: Crypto.keys(), receiver: Crypto.keys(), other: Crypto.keys()}
  end

  defp seal(context, plaintext \\ "the copy of Biscuit") do
    Crypto.seal(
      plaintext,
      %{"from_refuge" => "a", "to_refuge" => "b"},
      context.sender.sign_private,
      context.receiver.box_public
    )
  end

  defp open(sealed, sign_public, box_private) do
    Crypto.open(sealed.header, sealed.signature, sealed.payload, sign_public, box_private)
  end

  test "a sealed file opens for its receiver, with the key of its sender", context do
    sealed = seal(context)

    assert {:ok, "the copy of Biscuit", fields} =
             open(sealed, context.sender.sign_public, context.receiver.box_private)

    assert %{"from_refuge" => "a", "to_refuge" => "b"} = fields
    # The header holds no word of the payload.
    refute sealed.header =~ "Biscuit"
    refute sealed.payload =~ "Biscuit"
  end

  test "is refused with the key of another sender, or for another receiver", context do
    sealed = seal(context)

    assert {:error, :signature} =
             open(sealed, context.other.sign_public, context.receiver.box_private)

    assert {:error, :decrypt} =
             open(sealed, context.sender.sign_public, context.other.box_private)
  end

  test "is refused when any part changes", context do
    sealed = seal(context)
    flip = fn <<first, rest::binary>> -> <<Bitwise.bxor(first, 1), rest::binary>> end

    assert {:error, :payload} =
             open(
               %{sealed | payload: flip.(sealed.payload)},
               context.sender.sign_public,
               context.receiver.box_private
             )

    assert {:error, :signature} =
             open(
               %{sealed | header: String.replace(sealed.header, ~s("a"), ~s("c"))},
               context.sender.sign_public,
               context.receiver.box_private
             )

    assert {:error, :signature} =
             open(
               %{sealed | signature: flip.(sealed.signature)},
               context.sender.sign_public,
               context.receiver.box_private
             )

    # A header that the sender signs again, with a payload of another file,
    # does not decrypt: the payload holds its own header.
    other = seal(context, "another copy")

    fields =
      sealed.header
      |> Jason.decode!()
      |> Map.put("payload_sha256", Jason.decode!(other.header)["payload_sha256"])

    header = Jason.encode!(fields)
    signature = :crypto.sign(:eddsa, :none, header, [context.sender.sign_private, :ed25519])

    assert {:error, :decrypt} =
             Crypto.open(
               header,
               signature,
               other.payload,
               context.sender.sign_public,
               context.receiver.box_private
             )
  end

  test "refuses a key or a header of the wrong shape", context do
    sealed = seal(context)

    assert {:error, :signature} = open(sealed, "short", context.receiver.box_private)
    assert {:error, :payload} = open(sealed, context.sender.sign_public, "short")

    header = "[1, 2]"
    signature = :crypto.sign(:eddsa, :none, header, [context.sender.sign_private, :ed25519])

    assert {:error, :payload} =
             Crypto.open(
               header,
               signature,
               sealed.payload,
               context.sender.sign_public,
               context.receiver.box_private
             )
  end

  test "a private key at rest opens with the secret of the server alone" do
    key = :crypto.strong_rand_bytes(32)
    wrapped = Crypto.wrap(key, "the secret of this server, 32 bytes")

    refute wrapped =~ key
    assert Crypto.unwrap(wrapped, "the secret of this server, 32 bytes") == {:ok, key}
    assert Crypto.unwrap(wrapped, "another secret") == :error
    assert Crypto.unwrap("short", "the secret of this server, 32 bytes") == :error
  end

  test "a fingerprint is 32 hex digits in groups of four, the same for the same keys", context do
    print = Crypto.fingerprint(context.sender.sign_public, context.sender.box_public)

    assert print =~ ~r/\A[0-9A-F]{4}( [0-9A-F]{4}){7}\z/
    assert print == Crypto.fingerprint(context.sender.sign_public, context.sender.box_public)
    refute print == Crypto.fingerprint(context.other.sign_public, context.other.box_public)
  end
end
