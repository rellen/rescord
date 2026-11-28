defmodule Rescord.Notifications.WebPushTest do
  @moduledoc """
  The encryption of a push message (RFC 8291), the signature of the server
  (RFC 8292), and the push services that Rescord sends to (ADR 0106).
  """

  use ExUnit.Case, async: true

  alias Rescord.Notifications.WebPush

  defp bytes(text) do
    {:ok, bytes} = WebPush.decode(String.replace(text, ~r/\s/, ""))
    bytes
  end

  describe "encrypt/4" do
    # The example of RFC 8291, Appendix A: the keys of both sides, the
    # secret and the salt are fixed, so the message is too.
    test "writes the message of the example of RFC 8291" do
      device_key =
        bytes(
          "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4"
        )

      server = %{
        public:
          bytes(
            "BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8"
          ),
        private: bytes("yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw")
      }

      message =
        WebPush.encrypt(
          "When I grow up, I want to be a watermelon",
          device_key,
          bytes("BTBZMqHH6r4Tts7J_aSIgg"),
          salt: bytes("DGv6ra1nlYgDCS1FRnbzlw"),
          keys: server
        )

      assert message ==
               bytes("""
               DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN
               """)
    end

    test "uses a new key and a new salt for each message" do
      device = WebPush.keys()
      auth = :crypto.strong_rand_bytes(16)
      one = WebPush.encrypt("the same words", device.public, auth)
      two = WebPush.encrypt("the same words", device.public, auth)

      assert one != two
      refute one =~ "the same words"
    end
  end

  describe "vapid/4" do
    test "signs a token for the push service, which the public key of the server checks" do
      keys = WebPush.keys()
      now = ~U[2026-11-28 10:00:00Z]

      header =
        WebPush.vapid(
          "https://fcm.googleapis.com/fcm/send/abc",
          keys,
          "mailto:a@example.org",
          now
        )

      assert ["vapid t=" <> token, "k=" <> key] = String.split(header, ", ")
      assert bytes(key) == keys.public

      [head, claims, signature] = String.split(token, ".")
      <<r::256, s::256>> = bytes(signature)
      der = :public_key.der_encode(:"ECDSA-Sig-Value", {:"ECDSA-Sig-Value", r, s})

      assert :crypto.verify(:ecdsa, :sha256, head <> "." <> claims, der, [
               keys.public,
               :prime256v1
             ])

      claims = claims |> bytes() |> JSON.decode!()
      assert claims["aud"] == "https://fcm.googleapis.com"
      assert claims["sub"] == "mailto:a@example.org"
      # At most 24 hours, as RFC 8292 says.
      assert claims["exp"] > DateTime.to_unix(now)
      assert claims["exp"] <= DateTime.to_unix(now) + 24 * 3600
    end
  end

  describe "allowed_endpoint?/1" do
    test "takes the push services of the browsers" do
      for endpoint <- [
            "https://fcm.googleapis.com/fcm/send/abc",
            "https://updates.push.services.mozilla.com/wpush/v2/abc",
            "https://web.push.apple.com/abc",
            "https://wns2-par02p.notify.windows.com/w/?token=abc"
          ] do
        assert WebPush.allowed_endpoint?(endpoint), endpoint
      end
    end

    test "refuses any other address, so a person cannot make the server call it" do
      for endpoint <- [
            "https://evil.example.org/x",
            "https://push.apple.com.evil.example.org/x",
            "https://evilpush.apple.com/x",
            "http://fcm.googleapis.com/fcm/send/abc",
            "https://fcm.googleapis.com:8443/fcm/send/abc",
            "https://user@fcm.googleapis.com/fcm/send/abc",
            "https://127.0.0.1/x",
            "not an address",
            nil
          ] do
        refute WebPush.allowed_endpoint?(endpoint), inspect(endpoint)
      end
    end
  end

  describe "device_key?/1" do
    test "takes the bytes of an uncompressed point, and nothing else" do
      assert WebPush.device_key?(WebPush.keys().public)
      refute WebPush.device_key?(<<5>> <> :crypto.strong_rand_bytes(64))
      refute WebPush.device_key?(<<4>> <> :crypto.strong_rand_bytes(32))
      refute WebPush.device_key?("not a key")
    end
  end
end
