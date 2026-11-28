defmodule RescordWeb.ObanResolver do
  @moduledoc """
  Who may open Oban Web at `/root/oban`, and which actions they may take
  there (ADR 0110).

  Only a root user opens it. The plug and the hook `:require_root` of
  `RescordWeb.UserAuth` send anyone else away first; this resolver refuses
  them too, so that a change to the router alone cannot open the page.

  A root user watches every job and queue, and may take only the actions
  that stop or repeat work Rescord already made:

    * cancel a job, and retry one (with the arguments it has);
    * pause a queue, and resume it.

  The other actions stay off, because each one either loses a record of
  what happened or runs work that no action of Rescord made, past its
  policies: deleting a job; inserting or editing a job; scaling or stopping
  a queue, which changes what the configuration of the server says; and
  adding, editing, pausing or deleting a cron entry or a pruner rule.
  """

  @behaviour Oban.Web.Resolver

  @actions [cancel_jobs: true, retry_jobs: true, pause_queues: true]

  @doc "The actions that a root user may take."
  @spec actions() :: keyword(boolean())
  def actions, do: @actions

  # The page keeps the user in its session, which the page carries signed
  # but not encrypted, so it keeps the id alone.
  @impl true
  def resolve_user(conn) do
    case conn.assigns[:current_user] do
      %{root?: true, id: id} -> %{id: id, root?: true}
      _other -> nil
    end
  end

  @impl true
  def resolve_access(%{root?: true}), do: @actions
  def resolve_access(_other), do: {:forbidden, "/"}
end
