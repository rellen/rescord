defmodule Rescord.Health.Checks.RootUsers do
  @moduledoc """
  C8 of issue 38, for the server: no root user. Nobody can then make an
  organisation, set the providers of the assistant, or put a fault of
  another check right. `NotTheLastRoot` guards the revoke, but it reads
  and then acts. A new server has no root user until `bin/bootstrap-root`.
  """

  use Rescord.Health.Check

  @impl true
  def name, do: :root_users
  @impl true
  def scope, do: :server
  @impl true
  def cadence, do: :daily
  @impl true
  def title, do: "A server with no root user"

  @impl true
  def explain,
    do: "Nobody can manage this server. Run bin/bootstrap-root with the address of a person."

  @impl true
  def run(_context) do
    %{rows: [[roots]]} =
      Rescord.Repo.query!("select count(*) from public.users where is_root", [])

    if roots == 0, do: %{level: :fail, count: 1, ids: []}, else: ok()
  end
end
