defmodule Rescord.Ruby.Source do
  @moduledoc "Who wrote a message of a conversation: the member, or Ruby. A fixed list (ADR 0069)."

  use Ash.Type.Enum, values: [:user, :ruby]
end
