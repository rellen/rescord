defmodule Rescord.Ruby.Rating do
  @moduledoc "What a member said of a reply: it helped, or it did not. A fixed list (ADR 0069)."

  use Ash.Type.Enum, values: [:up, :down]
end
