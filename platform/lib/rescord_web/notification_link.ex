defmodule RescordWeb.NotificationLink do
  @moduledoc """
  Builds the address of the page of notifications of an organisation. A
  notification on a device opens it (issue 29). The core cannot name a
  route (ADR 0009): `config :rescord, :notifications_page_url` names
  `page/1`, and `Rescord.Notifications.Message` calls it.
  """

  use RescordWeb, :verified_routes

  @doc "The address of the page of notifications of the organisation with this short name."
  def page(short_name) when is_binary(short_name), do: url(~p"/o/#{short_name}/notifications")
end
