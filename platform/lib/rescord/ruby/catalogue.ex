defmodule Rescord.Ruby.Catalogue do
  @moduledoc """
  Each tool that Ruby may use (ADR 0069). A tool that is not here does not
  exist for Ruby, whatever a domain declares: `Rescord.Ruby.Toolbox` gives
  the loop the names of this list, and never `tools: true`.

  A tool is a line that a person wrote:

    * `name` - what the model calls;
    * `kind` - `:read`, or `:write` for a tool that changes a record. The
      loop never runs a write;
    * `source` - `:action` for a tool that a domain declares on an action,
      or `{:extra, module}` for a digest: a module with `name/0`, `tool/0`
      and `available?/2`.

  Three things are true before the model sees a tool: a domain declares it
  or a digest defines it, this list names it, and the role of the member
  allows it. `Rescord.Ruby.CatalogueTest` fails for a declared tool that
  is not here, for a destroy action, and for an action that never has a
  tool.
  """

  alias Rescord.Ruby.Digests

  @type entry :: %{
          name: atom,
          kind: :read | :write,
          source: :action | {:extra, module}
        }

  @entries [
    %{name: :find_residents, kind: :read, source: :action},
    %{name: :get_task, kind: :read, source: :action},
    %{name: :tasks_for_day, kind: :read, source: {:extra, Digests.TasksForDay}},
    %{name: :resident_profile, kind: :read, source: {:extra, Digests.ResidentProfile}},
    %{name: :resident_timeline, kind: :read, source: {:extra, Digests.ResidentTimeline}},
    %{name: :housing, kind: :read, source: {:extra, Digests.Housing}},
    %{name: :find_locations, kind: :read, source: :action}
  ]

  @doc "Each tool of Ruby."
  @spec entries() :: [entry]
  def entries, do: @entries

  @doc "The entry of a tool by the name that the model used, or `nil`. It makes no atom."
  @spec entry(term) :: entry | nil
  def entry(name) when is_binary(name),
    do: Enum.find(@entries, &(Atom.to_string(&1.name) == name))

  def entry(_other), do: nil

  @doc "Whether the name is a read tool of the catalogue."
  @spec read?(term) :: boolean
  def read?(name), do: match?(%{kind: :read}, entry(name))

  @doc """
  The tools that are on for an organisation with these settings and this
  profile. Each read is on. A write is never on yet: the phase that brings
  the first write brings its switch of the settings, and the kinds of
  provider that may write.
  """
  @spec on(term, term) :: [entry]
  def on(_settings, _profile), do: Enum.filter(@entries, &(&1.kind == :read))
end
