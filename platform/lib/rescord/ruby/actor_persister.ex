defmodule Rescord.Ruby.ActorPersister do
  @moduledoc """
  Puts the member into a job of Oban as an id, and reads the user back
  when the job runs (ADR 0069). The job of a reply holds no name and no
  address of a person.

  The user that comes back is the actor of Ruby
  (`Rescord.Ruby.Actor.for/1`): a root user has the grants of their role as
  a member, and no more. A user who is gone comes back as nobody, and the
  job then writes a reply that failed.
  """

  use AshOban.ActorPersister

  alias Rescord.Accounts.User
  alias Rescord.Ruby.Actor

  @impl true
  def store(%User{id: id}), do: %{"type" => "user", "id" => id}

  @impl true
  def lookup(%{"type" => "user", "id" => id}) do
    case Rescord.Accounts.user_for_job(id) do
      %User{} = user -> {:ok, Actor.for(user)}
      nil -> {:ok, nil}
    end
  end

  def lookup(_none), do: {:ok, nil}
end
