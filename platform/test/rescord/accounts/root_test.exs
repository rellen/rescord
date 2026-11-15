defmodule Rescord.Accounts.RootTest do
  @moduledoc """
  Holds the rules of the root user (`docs/domain.md`, section 5.1): the first
  one comes from `bootstrap_root/1`, a root user makes another one, and
  nobody else can.
  """

  use Rescord.DataCase, async: true

  import Rescord.AccountsFixtures

  alias Rescord.Accounts

  describe "bootstrap_root/1" do
    test "makes the first root user, and a user for an address with none" do
      address = unique_address()

      assert {:ok, root} = Accounts.bootstrap_root(address)
      assert root.root?
      assert to_string(root.email) == address
    end

    test "makes a user who exists a root user, and keeps one user for the address" do
      user = user!()

      assert {:ok, root} = Accounts.bootstrap_root(String.upcase(to_string(user.email)))
      assert root.id == user.id
      assert root.root?
    end

    test "does nothing when Rescord has a root user" do
      {:ok, _first} = Accounts.bootstrap_root(unique_address())
      address = unique_address()

      assert Accounts.bootstrap_root(address) == {:error, :root_exists}
      assert Accounts.user_by_email!(address, authorize?: false) == nil
    end
  end

  describe "a root user" do
    setup do
      {:ok, root} = Accounts.bootstrap_root(unique_address())
      {:ok, root: root}
    end

    test "makes another user a root user, and the version names who did it", %{root: root} do
      user = user!()

      assert {:ok, made} = Accounts.make_root(user, actor: root)
      assert made.root?

      assert [version] =
               Accounts.User.Version
               |> Ash.read!(authorize?: false)
               |> Enum.filter(&(&1.version_source_id == user.id))

      assert version.version_action_name == :make_root
      assert version.user_id == root.id
    end

    test "reads each user", %{root: root} do
      user = user!()

      assert Accounts.user_by_email!(to_string(user.email), actor: root).id == user.id
    end

    test "makes another root user an ordinary user", %{root: root} do
      {:ok, other} = Accounts.make_root(user!(), actor: root)

      assert {:ok, revoked} = Accounts.revoke_root(other, actor: root)
      refute revoked.root?
    end

    test "stays a root user while there is no other one", %{root: root} do
      assert {:error, %Ash.Error.Invalid{} = error} = Accounts.revoke_root(root, actor: root)
      assert Exception.message(error) =~ "is the last root user"

      assert [still] = Accounts.roots!(authorize?: false)
      assert still.id == root.id
    end
  end

  describe "a user who is not a root user" do
    setup do
      {:ok, root} = Accounts.bootstrap_root(unique_address())
      {:ok, root: root, user: user!()}
    end

    test "cannot make a root user, of themself or of another user", %{user: user} do
      for target <- [user, user!()] do
        assert {:error, %Ash.Error.Forbidden{}} = Accounts.make_root(target, actor: user)
      end

      assert [_only_the_first] = Accounts.roots!(authorize?: false)
    end

    test "cannot make a root user an ordinary user", %{root: root, user: user} do
      {:ok, _other} = Accounts.make_root(user!(), actor: root)

      assert {:error, %Ash.Error.Forbidden{}} = Accounts.revoke_root(root, actor: user)
    end

    test "reads only their own record", %{root: root, user: user} do
      assert Accounts.user_by_email!(to_string(user.email), actor: user).id == user.id
      assert Accounts.user_by_email!(to_string(root.email), actor: user) == nil
      assert Accounts.roots!(actor: user) == []
    end

    test "no action takes root? as input" do
      assert_raise Ash.Error.Invalid, ~r/root\?/, fn ->
        Accounts.User
        |> Ash.Changeset.for_create(:bootstrap_root, %{email: unique_address(), root?: false})
        |> Ash.create!(authorize?: false)
      end
    end
  end

  test "nobody who is not signed in reads a user" do
    user = user!()

    assert Accounts.user_by_email!(to_string(user.email)) == nil
  end
end
