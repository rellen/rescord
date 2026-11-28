defmodule Rescord.Notifications.Secrets do
  @moduledoc """
  The one module that opens a secret of the notifications (ADR 0106, as
  ADR 0068 holds for each secret): the private key of Web Push and the
  access token of ntfy in `Rescord.Notifications.Settings`, the secret
  `auth` of a device in `Rescord.Notifications.PushSubscription`, and the
  name of a topic in `Rescord.Notifications.NtfyTopic`.

  Each other read of those attributes is refused by
  `Rescord.Notifications.Settings.may_decrypt/4`. A value that cannot be
  opened is `:sealed`, never a raise.
  """

  @doc """
  Loads the secret `field` of `record`, opened, with no policy: for a
  job that sends a message. Returns `{:ok, record}` or `:sealed`.
  """
  @spec open(Ash.Resource.record(), atom) :: {:ok, Ash.Resource.record()} | :sealed
  def open(record, field), do: load(record, field, authorize?: false)

  @doc """
  Loads the secret `field` of `record`, opened, as the actor of `opts`:
  the policy of the record still decides. Returns `{:ok, record}` or
  `:sealed`.
  """
  @spec open_as(Ash.Resource.record(), atom, keyword) :: {:ok, Ash.Resource.record()} | :sealed
  def open_as(record, field, opts), do: load(record, field, actor: opts[:actor])

  defp load(record, field, options) do
    case Ash.load(record, field, [context: %{rescord_vault: :open}] ++ options) do
      {:ok, record} -> {:ok, record}
      {:error, _error} -> :sealed
    end
  rescue
    # A value that cannot be opened raises out of `Ash.load/3`.
    _error -> :sealed
  end
end
