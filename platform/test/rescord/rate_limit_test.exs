defmodule Rescord.RateLimitTest do
  @moduledoc """
  Holds `Rescord.RateLimit`, Hammer and `AshRateLimiter` together (ADR 0020):
  an action with a limit refuses the call that is over it, and counts each
  key by itself.
  """

  use ExUnit.Case, async: true

  alias Rescord.RateLimitFixtures.Request

  # Each test counts under an address of its own, so the tests share no count.
  defp address, do: "person-#{System.unique_integer([:positive])}@example.com"

  defp request(address) do
    Request |> Ash.Changeset.for_create(:create, %{address: address}) |> Ash.create()
  end

  test "the application runs the rate limiter" do
    assert {:allow, 1} = Rescord.RateLimit.hit("test/alive/#{address()}", 1_000, 1)
  end

  test "an action allows the calls within its limit, and refuses the next one" do
    address = address()

    assert {:ok, _} = request(address)
    assert {:ok, _} = request(address)

    assert {:error, %Ash.Error.Forbidden{errors: errors}} = request(address)
    assert [%AshRateLimiter.LimitExceeded{limit: 2}] = errors
  end

  test "a refusal for one key does not count against another key" do
    busy = address()

    assert {:ok, _} = request(busy)
    assert {:ok, _} = request(busy)
    assert {:error, _} = request(busy)

    assert {:ok, _} = request(address())
  end

  test "the count of a key ends with its period" do
    key = "test/period/#{address()}"

    assert {:allow, 1} = Rescord.RateLimit.hit(key, 50, 1)
    assert {:deny, _} = Rescord.RateLimit.hit(key, 50, 1)

    Process.sleep(120)

    assert {:allow, 1} = Rescord.RateLimit.hit(key, 50, 1)
  end
end
