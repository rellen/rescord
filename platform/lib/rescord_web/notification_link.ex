defmodule RescordWeb.NotificationLink do
  @moduledoc """
  Builds the address of the page of notifications of an organisation. A
  notification on a device opens it (issue 29). The core cannot name a
  route (ADR 0009): `config :rescord, :notifications_page_url` names
  `page/1`, and `Rescord.Notifications.Message` calls it. An alert of the
  sanity checks opens `/root/health`: `config :rescord, :health_page_url`
  names `health/0`, and `Rescord.Health.Alerts` calls it.
  """

  use RescordWeb, :verified_routes

  @doc "The address of the page of notifications of the organisation with this short name."
  def page(short_name) when is_binary(short_name), do: url(~p"/o/#{short_name}/notifications")

  @doc "The address of the page of the sanity checks, which an alert opens (ADR 0114)."
  def health, do: url(~p"/root/health")
end
