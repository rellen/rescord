defmodule Rescord.Ruby.Grants do
  @moduledoc """
  What a role can do with Ruby (ADR 0024 and ADR 0069).

  No role reads a conversation by default. The power `:ruby` gives a
  member their own conversations and messages, the scope `own`, and
  nothing of another member. It decides who can spend the allowance of
  the organisation, and not what a person can learn: each role reads the
  records already.

  The power `:settings` reads each conversation and each message of the
  organisation, and changes none: a rescue can answer for what its
  volunteers were told. The page of Ruby says so to each member. The same
  power reads and changes how the organisation uses Ruby
  (`Rescord.Ruby.Settings`), which no role reads without it.

  An action that only Rescord runs, such as `touch`, is in no grant.
  `Rescord.Ruby.Provider` is not here: only a root user reaches it, by its
  own policy.
  """

  @behaviour Rescord.Accounts.Grants

  import Ash.Expr, only: [expr: 1, actor: 1]

  alias Rescord.Ruby.{Conversation, Message, Settings}

  @impl true
  def reads, do: []

  @impl true
  def powers do
    %{
      # These add to the power `settings` of the accounts.
      settings: [
        {Settings, :read, :all},
        {Settings, :set, :all},
        {Settings, :change, :all},
        {Conversation, :read, :all},
        {Conversation, :of_member, :all},
        {Message, :read, :all}
      ],
      ruby: [
        {Conversation, :read, :own},
        {Conversation, :mine, :own},
        # A create has no record yet: the action makes the actor the owner.
        {Conversation, :start, :all},
        {Conversation, :rename, :own},
        {Conversation, :remove, :own},
        {Message, :read, :own},
        # `say` refuses a conversation of another person.
        {Message, :say, :all},
        {Message, :rate, :own},
        {Message, :stop, :own}
      ]
    }
  end

  # Each source is asked about each resource, so this answers only for
  # the resources of Ruby.
  @impl true
  def filter(resource, :own) when resource in [Conversation, Message],
    do: expr(owner_id == ^actor(:id))

  def filter(_resource, _scope), do: nil
end
