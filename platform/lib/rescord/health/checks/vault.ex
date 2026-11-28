defmodule Rescord.Health.Checks.Vault do
  @moduledoc """
  C6 of issue 38: the values that the secret of the server encrypts still
  open (ADR 0068). It counts as `bin/check` does: each value of
  `Rescord.Vault` and each private key of a transfer is opened, and what it
  opened is let go at once. A value that no secret opens is a fault; a
  value under the previous secret alone, or a previous secret that is still
  set, is a note.
  """

  use Rescord.Health.Check

  @impl true
  def name, do: :vault
  @impl true
  def scope, do: :server
  @impl true
  def cadence, do: :daily
  @impl true
  def title, do: "Encrypted values that the secret of the server opens"

  @impl true
  def explain,
    do:
      "A fault: RESCORD_KEY_SECRET is not the secret that encrypted some values, " <>
        "for example after a change of the secret in the wrong order. Set the old secret " <>
        "as RESCORD_KEY_SECRET_PREVIOUS and run bin/rotate-vault. A note: run bin/rotate-vault, " <>
        "then take RESCORD_KEY_SECRET_PREVIOUS out."

  @impl true
  def run(_context) do
    counts =
      Map.merge(Rescord.Vault.count(), Rescord.Transfers.count_keys(), fn _kind, a, b -> a + b end)

    previous? = is_binary(Application.get_env(:rescord, Rescord.Vault, [])[:previous_secret])

    cond do
      counts.sealed > 0 -> %{level: :fail, count: counts.sealed, ids: []}
      counts.previous > 0 -> %{level: :note, count: counts.previous, ids: []}
      previous? -> %{level: :note, count: 0, ids: []}
      true -> ok()
    end
  end
end
