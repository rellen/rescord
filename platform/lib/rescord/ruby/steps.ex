defmodule Rescord.Ruby.Steps do
  @moduledoc """
  The steps of a reply of Ruby (ADR 0069): one for each call of a tool,
  in the order in which they started. A reply keeps them in `steps`, and
  the page of the conversation hears each one as it changes.

  A step is what code made of the call, and never the result of the tool,
  which holds raw records:

      %{
        "call_id" => "toolu_01…",
        "tool" => "tasks_for_day",
        "arguments" => %{"date" => "2026-11-28"},
        "state" => "running" | "done" | "failed" | "stopped",
        "count" => 1,
        "refs" => [%{"ref" => "resident:<uuid>", "label" => "Biscuit", "detail" => "Guinea pig"}]
      }

  The outline of a result is its count and its references: each map in
  the result with a `ref` and a `label`, as each digest names a record
  (`Rescord.Ruby.Digests.Shape`), and for an action tool of a domain each
  record that it returns, with its `id` and its name. The count is the
  `count` of the result, the length of a list, or the number that a read
  of a count returns, and else `nil`: a profile names records, and counts
  none.

  A step keeps only the arguments that its words use, and no other value
  that the model sent.

  A step holds at most 50 references. The keys are text: the steps
  are a column of JSON.
  """

  # The most references that a step keeps.
  @most 50

  # The kind of reference of the records of each action tool, which
  # returns its records with their ids and no `ref`.
  @kinds %{
    "find_residents" => "resident",
    "find_locations" => "location",
    "find_items" => "item",
    "get_task" => "task"
  }

  # The arguments that a step keeps, for its words (`RescordWeb.RubyWords`).
  @shown %{"care_overview" => ["question"], "tasks_for_day" => ["date"]}

  @type t :: %{String.t() => term}

  @doc "The steps with one more, which runs: a call of a tool that the model made."
  @spec started([t], map) :: [t]
  def started(steps, %{id: id, name: name} = call) when is_binary(id) and is_binary(name) do
    step = %{
      "call_id" => id,
      "tool" => name,
      "arguments" => arguments(name, Map.get(call, :arguments)),
      "state" => "running",
      "count" => nil,
      "refs" => []
    }

    steps ++ [step]
  end

  @doc "The steps, with the outline of the result of one call in its step."
  @spec ended([t], map) :: [t]
  def ended(steps, %{id: id, result: result}) do
    Enum.map(steps, fn
      %{"call_id" => ^id, "tool" => tool} = step -> Map.merge(step, outline(tool, result))
      step -> step
    end)
  end

  @doc """
  The steps at the end of a reply: a step that still runs did not end. It
  stopped, when the member stopped the reply, and failed in each other
  case.
  """
  @spec closed([t], atom) :: [t]
  def closed(steps, state) do
    ended = if state == :stopped, do: "stopped", else: "failed"

    Enum.map(steps, fn
      %{"state" => "running"} = step -> %{step | "state" => ended}
      step -> step
    end)
  end

  @doc "The step of a call, or `nil`."
  @spec find([t], String.t()) :: t | nil
  def find(steps, call_id), do: Enum.find(steps, &(&1["call_id"] == call_id))

  @doc "Each reference that the steps returned, as text such as `resident:<uuid>`."
  @spec refs([t] | nil) :: [String.t()]
  def refs(steps) when is_list(steps),
    do: for(%{"refs" => refs} <- steps, %{"ref" => ref} <- refs, uniq: true, do: ref)

  def refs(_none), do: []

  @doc """
  What code makes of the result of a tool: the state of the step, the
  count and the references. A refusal or a fault is a failed step, with
  no words of the result.
  """
  @spec outline(String.t(), term) :: map
  def outline(tool, {:ok, content, _raw}), do: outline(tool, {:ok, content})

  def outline(tool, {:ok, content}) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, %{"error" => _error}} -> failed()
      {:ok, decoded} -> done(tool, decoded)
      {:error, _not_json} -> %{"state" => "done", "count" => nil, "refs" => []}
    end
  end

  def outline(_tool, _error), do: failed()

  defp failed, do: %{"state" => "failed", "count" => nil, "refs" => []}

  defp done(tool, decoded) do
    refs =
      (action_refs(Map.get(@kinds, tool), decoded) ++ Enum.reverse(collect(decoded, [])))
      |> Enum.uniq_by(& &1["ref"])

    %{"state" => "done", "count" => count(decoded), "refs" => Enum.take(refs, @most)}
  end

  # The count of the result: its own `count`, the records of a list or of
  # a page with no more, or the number that a read of a count gives. Else no count, rather than
  # a count of each record that the result names on the way.
  defp count(%{"count" => count}) when is_integer(count) and count >= 0, do: count
  defp count(list) when is_list(list), do: length(list)

  # A page of a read: its records, when there are no more.
  defp count(%{"results" => list} = page) when is_list(list),
    do: if(page["has_more"] == true, do: nil, else: length(list))

  defp count(count) when is_integer(count) and count >= 0, do: count
  defp count(_other), do: nil

  # The records of an action tool: the items of the list or of the page
  # that it returns, or the one record,
  # each with its id and its name. The records that they load are no
  # records of the kind of the tool.
  defp action_refs(kind, list) when is_binary(kind) and is_list(list) do
    for %{"id" => id} = record <- list,
        is_binary(id),
        label = record["name"] || record["title"],
        is_binary(label),
        do: reference(kind <> ":" <> id, label, nil)
  end

  defp action_refs(kind, %{"results" => list}) when is_list(list), do: action_refs(kind, list)
  defp action_refs(kind, %{"id" => _id} = record), do: action_refs(kind, [record])
  defp action_refs(_kind, _result), do: []

  # Each record of the result that names itself with a `ref` and a
  # `label`, depth first.
  defp collect(%{"ref" => ref, "label" => label} = record, found)
       when is_binary(ref) and is_binary(label) do
    record
    |> Map.drop(["ref", "label"])
    |> Map.values()
    |> Enum.reduce([reference(ref, label, record["detail"]) | found], &collect/2)
  end

  defp collect(%{} = map, found), do: map |> Map.values() |> Enum.reduce(found, &collect/2)
  defp collect(list, found) when is_list(list), do: Enum.reduce(list, found, &collect/2)
  defp collect(_value, found), do: found

  defp reference(ref, label, detail) when is_binary(detail),
    do: %{"ref" => ref, "label" => label, "detail" => detail}

  defp reference(ref, label, _detail), do: %{"ref" => ref, "label" => label}

  # Only the arguments that the words of a step use, each a short text:
  # the rest of what the model sent stays out of the step, the page and
  # any report of a crash.
  defp arguments(tool, arguments) when is_binary(arguments) do
    case Jason.decode(arguments) do
      {:ok, %{} = arguments} -> arguments(tool, arguments)
      _other -> %{}
    end
  end

  defp arguments(tool, %{} = arguments) do
    for key <- Map.get(@shown, tool, []),
        value = arguments[key],
        is_binary(value) and byte_size(value) <= 40,
        into: %{},
        do: {key, value}
  end

  defp arguments(_tool, _other), do: %{}
end
