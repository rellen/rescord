defmodule Rescord.Ruby.ReplyState do
  @moduledoc """
  Where a reply of Ruby stands (ADR 0069). A fixed list.

    * `:streaming` - the job writes the reply now;
    * `:awaiting` - the reply waits for the member, who has a proposal to
      confirm or to discard;
    * `:complete` - the reply ended;
    * `:failed` - the reply ended with a fault, and its reason says which;
    * `:stopped` - the member stopped it.
  """

  use Ash.Type.Enum, values: [:streaming, :awaiting, :complete, :failed, :stopped]
end
