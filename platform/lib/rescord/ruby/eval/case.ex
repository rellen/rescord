defmodule Rescord.Ruby.Eval.Case do
  @moduledoc """
  One question of the evaluation set of Ruby, and what a right answer must
  and must not hold. `Rescord.Ruby.Eval.Score` checks each field by code.

    * `id` - a name that stays, for the table and for a report of a
      failure;
    * `group` - what the question tempts: `:lookup`, `:none`, `:care`,
      `:injection`, and the groups of the later phases;
    * `as` - who asks: the key of a role of the seed;
    * `about` - the reference of the record that the page was on, or none;
    * `say` - the question. A list is a conversation of several turns, and
      the checks are for its last answer;
    * `must_call` - names of tools that the reply calls, as a set and in no
      order;
    * `must_not_call` - names of tools that the question does not need;
    * `must_link` - ids of records that the answer links;
    * `must_say` and `must_not_say` - patterns for the text of the answer;
    * `max_requests`, `max_words`, `max_seconds` - the limits of the reply.
  """

  @enforce_keys [:id, :group, :say]
  defstruct [
    :id,
    :group,
    :say,
    :about,
    as: :member,
    must_call: [],
    must_not_call: [],
    must_link: [],
    must_say: [],
    must_not_say: [],
    max_requests: 4,
    max_words: 120,
    max_seconds: 60
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          group: atom,
          say: String.t() | [String.t()],
          about: String.t() | nil,
          as: atom,
          must_call: [String.t()],
          must_not_call: [String.t()],
          must_link: [String.t()],
          must_say: [Regex.t()],
          must_not_say: [Regex.t()],
          max_requests: pos_integer,
          max_words: pos_integer,
          max_seconds: pos_integer
        }
end
