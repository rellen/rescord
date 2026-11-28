defmodule Rescord.Ruby.Actor do
  @moduledoc """
  The actor of each tool call of Ruby (ADR 0069): the member, with the
  level of a root user turned off. This is the only place that makes it.

  The policy of each resource starts with a bypass for a root user. With
  this actor the bypass never applies, so a tool call of a root user who
  is a member has the rights of the role of that member, and a root user
  who is no member reads nothing through Ruby.
  """

  alias Rescord.Accounts.User

  @spec for(User.t()) :: User.t()
  def for(%User{} = user), do: %{user | root?: false}
end
