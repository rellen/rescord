defmodule Rescord.Health.Checks.SecretsSet do
  @moduledoc """
  C7 of issue 38: a setting that says a secret is set, with no encrypted
  value behind it. The pages and `bin/check` trust the marker and decrypt
  nothing, and `Rescord.Vault.count/0` skips an empty column, so neither
  sees it. The markers:

  - a provider of the assistant: `key_set_at` and `encrypted_api_key`;
  - the notifications: `vapid_public_key` (or `push_on`) and
    `encrypted_vapid_private_key`, `ntfy_token_set_at` and
    `encrypted_ntfy_token`;
  - the usage counts: `token_set_at` and `encrypted_token`.

  The ids are those of the rows.
  """

  use Rescord.Health.Check

  @impl true
  def name, do: :secrets_set
  @impl true
  def scope, do: :server
  @impl true
  def cadence, do: :daily
  @impl true
  def title, do: "Secrets that a setting says are set, and are not there"

  @impl true
  def explain,
    do:
      "A setting says that it has a key or a token, and has none. Set the key or the token " <>
        "again on its root page: the assistant at /root/ruby, the devices and ntfy at " <>
        "/root/push, the usage counts at /root/usage."

  @impl true
  def run(_context) do
    query("""
    select id from public.ruby_providers
      where archived_at is null and key_set_at is not null and encrypted_api_key is null
    union all
    select id from public.notification_settings
      where ((vapid_public_key is not null or push_on) and encrypted_vapid_private_key is null)
         or (ntfy_token_set_at is not null and encrypted_ntfy_token is null)
    union all
    select id from public.usage_settings
      where token_set_at is not null and encrypted_token is null
    """)
    |> found(:fail)
  end
end
