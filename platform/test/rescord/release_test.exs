defmodule Rescord.ReleaseTest do
  @moduledoc """
  Holds the tasks of a release (ADR 0044) that a test can run in its
  transaction: the first root user, one time. `migrate/0` runs in the
  image and the package, against a database of its own.
  """

  use Rescord.DataCase, async: false

  import ExUnit.CaptureIO

  alias Rescord.{Accounts, Release}

  test "makes the first root user, and no second one" do
    output = capture_io(fn -> assert :ok = Release.bootstrap_root("first@example.org") end)
    assert output =~ "first@example.org is the first root user."

    assert {:ok, [root]} = Accounts.roots(authorize?: false)
    assert to_string(root.email) == "first@example.org"

    output =
      capture_io(fn ->
        assert {:error, :root_exists} = Release.bootstrap_root("second@example.org")
      end)

    assert output =~ "Rescord has a root user already."
  end
end
