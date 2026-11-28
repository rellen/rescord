defmodule Rescord.Ruby.Rating do
  @moduledoc "What a member said of a reply: it was right (`:up`), or it was not (`:down`). A fixed list (ADR 0069)."

  use Ash.Type.Enum, values: [:up, :down]
end
