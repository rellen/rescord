defmodule Rescord.Ruby.StepsTest do
  @moduledoc """
  Holds what code makes of a call of a tool (ADR 0069): a step with the
  count and the references of the result, and never the result itself,
  and only the arguments that the words of a step use.
  """

  use ExUnit.Case, async: true

  alias Rescord.Ruby.Steps

  @biscuit "resident:6f1c2a52-4f5e-4d43-9a8e-1f0b7e0c9a11"
  @pen "location:0b8f4c1e-5f6a-4c2d-8e9b-2a3c4d5e6f70"

  defp call(id, name, arguments \\ %{}), do: %{id: id, name: name, arguments: arguments}

  describe "a call of a tool" do
    test "starts a step that runs, with the arguments that its words use" do
      steps =
        []
        |> Steps.started(call("a", "tasks_for_day", ~s({"date":"2026-11-28","limit":5})))
        |> Steps.started(call("b", "care_overview", %{"question" => "on_medication"}))
        |> Steps.started(call("c", "resident_profile", %{"resident" => "Biscuit"}))

      assert [
               %{
                 "call_id" => "a",
                 "tool" => "tasks_for_day",
                 "arguments" => %{"date" => "2026-11-28"},
                 "state" => "running",
                 "count" => nil,
                 "refs" => []
               },
               %{"call_id" => "b", "arguments" => %{"question" => "on_medication"}},
               %{"call_id" => "c", "arguments" => %{}}
             ] = steps

      # No other value that the model sent, and no long one.
      refute inspect(steps) =~ "Biscuit"
      long = String.duplicate("x", 41)

      assert [%{"arguments" => %{}}] =
               Steps.started([], call("d", "tasks_for_day", %{"date" => long}))

      assert [%{"arguments" => %{}}] =
               Steps.started([], call("d", "tasks_for_day", %{"date" => 1}))

      # Arguments that are no object are none.
      assert [%{"arguments" => %{}}] = Steps.started([], call("e", "tasks_for_day", "[1]"))
      assert [%{"arguments" => %{}}] = Steps.started([], call("e", "tasks_for_day", nil))
    end

    test "ends in its own step, with the references of the result and no word of it" do
      result =
        Jason.encode!(%{
          "resident" => %{"ref" => @biscuit, "label" => "Biscuit", "detail" => "Guinea pig"},
          "placement" => %{"location" => %{"ref" => @pen, "label" => "Pen 2"}},
          "notes_text" => "Shy with new people"
        })

      steps =
        []
        |> Steps.started(call("a", "resident_profile"))
        |> Steps.started(call("b", "housing"))
        |> Steps.ended(%{id: "a", result: {:ok, result, %{raw: :records}}})

      assert [%{"call_id" => "a", "state" => "done"} = done, %{"state" => "running"}] = steps

      # A profile names records, and counts none.
      assert done["count"] == nil

      # The order of the keys of a map is no order of the records.
      assert Enum.sort_by(done["refs"], & &1["ref"]) == [
               %{"ref" => @pen, "label" => "Pen 2"},
               %{"ref" => @biscuit, "label" => "Biscuit", "detail" => "Guinea pig"}
             ]

      refute inspect(steps) =~ "Shy"
      refute inspect(steps) =~ "raw"
    end

    test "takes the count of the result, of a list, or of a read of a count" do
      result =
        Jason.encode!(%{"count" => 19, "tasks" => [%{"ref" => "task:1", "label" => "Feed"}]})

      assert %{"state" => "done", "count" => 19, "refs" => [%{"ref" => "task:1"}]} =
               Steps.outline("tasks_for_day", {:ok, result})

      assert %{"count" => 12, "refs" => []} = Steps.outline("find_residents", {:ok, "12"})
      assert %{"count" => nil} = Steps.outline("find_residents", {:ok, "true"})
      assert %{"count" => nil} = Steps.outline("find_residents", {:ok, "-1"})
    end

    test "names the records that an action tool returns by their ids and names" do
      result =
        Jason.encode!([
          %{"id" => "6f1c2a52", "name" => "Biscuit", "species" => "Guinea pig"},
          %{"id" => "7a2d3b63", "name" => "Clover"},
          %{"id" => "8b3e4c74"}
        ])

      assert %{"state" => "done", "count" => 3, "refs" => refs} =
               Steps.outline("find_residents", {:ok, result})

      assert refs == [
               %{"ref" => "resident:6f1c2a52", "label" => "Biscuit"},
               %{"ref" => "resident:7a2d3b63", "label" => "Clover"}
             ]

      # A tool that the list of kinds does not name gives no reference from
      # an id.
      assert %{"count" => 3, "refs" => []} = Steps.outline("housing", {:ok, result})
    end

    test "names the records of a page that a read returns, and counts them when there are no more" do
      records = [
        %{"id" => "6f1c2a52", "name" => "Biscuit"},
        %{"id" => "7a2d3b63", "name" => "Clover"}
      ]

      page = %{"results" => records, "limit" => 2, "offset" => 0, "has_more" => false}

      assert %{
               "count" => 2,
               "refs" => [%{"ref" => "resident:6f1c2a52"}, %{"ref" => "resident:7a2d3b63"}]
             } =
               Steps.outline("find_residents", {:ok, Jason.encode!(page)})

      more = %{page | "has_more" => true}

      assert %{"count" => nil, "refs" => [_, _]} =
               Steps.outline("find_residents", {:ok, Jason.encode!(more)})

      counted = Map.put(more, "count", 40)
      assert %{"count" => 40} = Steps.outline("find_residents", {:ok, Jason.encode!(counted)})
    end

    test "a record that an action tool loads is no record of the kind of the tool" do
      task =
        Jason.encode!(%{
          "id" => "1d2e3f40",
          "title" => "Feed the goats",
          "subjects" => [%{"resident" => %{"id" => "6f1c2a52", "name" => "Biscuit"}}]
        })

      assert %{
               "count" => nil,
               "refs" => [%{"ref" => "task:1d2e3f40", "label" => "Feed the goats"}]
             } =
               Steps.outline("get_task", {:ok, task})
    end

    test "keeps each reference once, and at most fifty" do
      many = for n <- 1..60, do: %{"ref" => "item:#{n}", "label" => "Item #{n}"}
      result = Jason.encode!(%{"items" => many ++ many})

      assert %{"refs" => refs} = Steps.outline("stock_levels", {:ok, result})
      assert length(refs) == 50
      assert hd(refs)["ref"] == "item:1"
    end

    test "fails for a refusal or a fault, with no word of the result" do
      assert Steps.outline("housing", {:ok, ~s({"error":"You cannot read Barn"})}) ==
               %{"state" => "failed", "count" => nil, "refs" => []}

      assert %{"state" => "failed"} = Steps.outline("housing", {:error, "Barn is not there"})
      assert %{"state" => "failed"} = Steps.outline("housing", :timeout)

      # A result that is no JSON is done, with nothing to count.
      assert Steps.outline("housing", {:ok, "Two pens"}) ==
               %{"state" => "done", "count" => nil, "refs" => []}
    end
  end

  test "a reply that ends with a step that runs closes it: stopped, or failed" do
    steps =
      []
      |> Steps.started(call("a", "housing"))
      |> Steps.started(call("b", "stock_levels"))
      |> Steps.ended(%{id: "a", result: {:ok, "{}"}})

    assert [%{"state" => "done"}, %{"state" => "failed"}] = Steps.closed(steps, :failed)
    assert [%{"state" => "done"}, %{"state" => "stopped"}] = Steps.closed(steps, :stopped)
    assert %{"tool" => "stock_levels"} = Steps.find(steps, "b")
    assert Steps.find(steps, "c") == nil
  end

  test "the references of the steps, each once" do
    steps = [
      %{
        "refs" => [
          %{"ref" => @biscuit, "label" => "Biscuit"},
          %{"ref" => @pen, "label" => "Pen 2"}
        ]
      },
      %{"refs" => [%{"ref" => @biscuit, "label" => "Biscuit"}]},
      %{"refs" => []}
    ]

    assert Steps.refs(steps) == [@biscuit, @pen]
    assert Steps.refs(nil) == []
  end
end
