defmodule Rescord.VaultTest do
  @moduledoc """
  The vault of the settings (ADR 0068): what it encrypts, only a secret of
  this server opens, and a change of the secret loses nothing.

  The tests change the secret of the server, so they do not run beside
  others.
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.RubyFixtures

  alias Rescord.Ruby.LLM
  alias Rescord.{Transfers, Vault}
  alias Rescord.Vault.Sealed

  @old "the secret that the server had before, 32 bytes"
  @new "the secret that the server has now, 32 bytes long"
  @other "a secret that this server never had, 32 bytes long"

  describe "a value" do
    test "opens with the secret that encrypted it" do
      sealed = Vault.encrypt!("a value")

      assert Vault.decrypt!(sealed) == "a value"
      assert Vault.current?(sealed)
      refute sealed =~ "a value"
    end

    test "is different each time, for the same text" do
      refute Vault.encrypt!("a value") == Vault.encrypt!("a value")
    end

    test "does not open after a change of one bit" do
      <<start::binary-size(20), byte, rest::binary>> = Vault.encrypt!("a value")

      assert_raise Sealed, fn ->
        Vault.decrypt!(<<start::binary, Bitwise.bxor(byte, 1), rest::binary>>)
      end
    end

    test "does not open when it is no value of the vault" do
      assert_raise Sealed, fn -> Vault.decrypt!("") end
      assert_raise Sealed, fn -> Vault.decrypt!("some other bytes, of any length at all") end
      refute Vault.current?("some other bytes")
    end

    test "does not open with another secret" do
      sealed = Vault.encrypt!("a value")
      secrets!(@other)

      assert_raise Sealed, fn -> Vault.decrypt!(sealed) end
    end

    test "of the previous secret opens while the server has both" do
      secrets!(@old)
      sealed = Vault.encrypt!("a value")

      secrets!(@new, @old)

      assert Vault.decrypt!(sealed) == "a value"
      refute Vault.current?(sealed)
      # A new value has the secret of today.
      assert Vault.current?(Vault.encrypt!("another value"))
    end
  end

  describe "a change of the secret of the server" do
    setup do
      secrets!(@old)
      root = root!()
      %{root: root, provider: provider!(root)}
    end

    test "finds each resource with a secret, with no list" do
      assert Rescord.Ruby.Provider in Vault.resources()
    end

    test "reads a key of the old secret, and rotate writes it again", %{provider: provider} do
      assert Vault.count() == %{current: 1, previous: 0, sealed: 0}

      secrets!(@new, @old)

      assert Vault.count() == %{current: 0, previous: 1, sealed: 0}
      assert {:ok, %{api_key: opened}} = LLM.profile_of(provider)
      assert opened == key()

      # The counts are those from before the run.
      assert Vault.rotate() == %{current: 0, previous: 1, sealed: 0}
      assert Vault.count() == %{current: 1, previous: 0, sealed: 0}
      # A second run changes nothing.
      assert Vault.rotate() == %{current: 1, previous: 0, sealed: 0}

      # The old secret can go now.
      secrets!(@new)
      assert Vault.count() == %{current: 1, previous: 0, sealed: 0}
      assert {:ok, %{api_key: ^opened}} = LLM.profile_of(provider)
    end

    test "writes no version, and changes no other column", %{provider: provider} do
      row = fn ->
        Repo.query!(
          "select (to_jsonb(p) - 'encrypted_api_key')::text from ruby_providers p where id = $1",
          [Ecto.UUID.dump!(provider.id)]
        ).rows
      end

      versions = fn -> Repo.query!("select count(*) from ruby_providers_versions").rows end
      before = {row.(), versions.()}

      secrets!(@new, @old)
      Vault.rotate()

      assert {row.(), versions.()} == before
    end

    test "without the old secret leaves a key that nothing opens", %{provider: provider} do
      secrets!(@new)

      assert Vault.count() == %{current: 0, previous: 0, sealed: 1}
      assert LLM.profile_of(provider) == {:error, :key_refused}
      # Rotate leaves it as it is.
      assert Vault.rotate() == %{current: 0, previous: 0, sealed: 1}

      # The old secret opens it still.
      secrets!(@old)
      assert {:ok, _profile} = LLM.profile_of(provider)
    end

    test "leaves a provider with no key out of the counts", %{root: root} do
      Rescord.Ruby.add_provider!(%{name: "The shed server", kind: :ollama, model: "a-model"},
        actor: root
      )

      assert Vault.count() == %{current: 1, previous: 0, sealed: 0}
    end
  end

  describe "the keys of the transfers, at a change of the secret" do
    setup do
      secrets!(@old)
      root = root!()
      %{organisation: organisation!(root)}
    end

    test "open with the old secret, and are wrapped again", %{organisation: organisation} do
      keys = Transfers.Keys.of(organisation)
      assert Transfers.count_keys() == %{current: 1, previous: 0, sealed: 0}

      secrets!(@new, @old)

      assert Transfers.count_keys() == %{current: 0, previous: 1, sealed: 0}
      assert Transfers.Keys.of(organisation) == keys

      assert Transfers.rewrap_keys() == %{current: 0, previous: 1, sealed: 0}
      assert Transfers.rewrap_keys() == %{current: 1, previous: 0, sealed: 0}

      secrets!(@new)
      assert Transfers.Keys.of(organisation) == keys
    end

    test "that no secret opens are counted, and stay", %{organisation: organisation} do
      Transfers.Keys.of(organisation)
      secrets!(@new)

      assert Transfers.count_keys() == %{current: 0, previous: 0, sealed: 1}
      assert Transfers.rewrap_keys() == %{current: 0, previous: 0, sealed: 1}
    end
  end
end
