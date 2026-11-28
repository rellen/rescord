defmodule Rescord.Usage.Document do
  @moduledoc """
  The document of one day that Rescord sends (ADR 0098), in one of two
  formats, character for character as a send writes it. The page
  `/root/usage` shows the same bytes first.

  ## `otlp`: the metrics of OpenTelemetry, as JSON over HTTP

  One `ExportMetricsServiceRequest` of OTLP 1.x in its JSON form, which any
  OTLP endpoint takes at `/v1/metrics`, such as an OpenTelemetry Collector.
  It holds one metric, `rescord.usage.count`: a monotonic sum with the
  temporality delta (`aggregationTemporality` 1), one point for each count
  of the day, with the attributes `feature`, `kind` and `item`. The point
  starts at the midnight of the day and ends at the next one, in UTC. A
  number of 64 bits is a string, as OTLP writes it in JSON.

  The resource has `service.name` (`rescord`), `service.version`, and
  `service.instance.id`, the random id of the installation. Nothing else:
  no host, no process, no node name, which the SDK of OpenTelemetry would
  add.

  ## `json`: the plain document of Rescord

      {"schema": "rescord.usage/1", "installation": "…", "rescord": "0.3.0",
       "day": "2026-11-27", "counts": [{"feature": "expenses", "kind": "action",
       "item": "expenses.expense.approve", "count": 4}]}

  A test (`test/2`) sends the same form with no count: for `json` it says
  `"test": true`, and for `otlp` it has the resource and no metric.

  Nothing in either names a person, an organisation, a record or a host.
  A new field is a decision of the maintainer.
  """

  alias Rescord.Usage.Count

  @nanos_a_day 86_400 * 1_000_000_000

  @doc """
  The document of `day` with its counts, as the bytes of JSON. The keys
  keep their order, so the page and the send show the same text.
  """
  @spec day(:otlp | :json, String.t(), Date.t(), [Count.t()]) :: String.t()
  def day(format, installation_id, %Date{} = day, counts) do
    counts = Enum.sort_by(counts, &{&1.feature, &1.kind, &1.item})
    format |> build(installation_id, day, counts) |> encode()
  end

  @doc "The document of a test: the same form, with no count."
  @spec test(:otlp | :json, String.t()) :: String.t()
  def test(:json, installation_id) do
    encode([
      {"schema", "rescord.usage/1"},
      {"installation", installation_id},
      {"rescord", Rescord.version()},
      {"test", true},
      {"counts", []}
    ])
  end

  def test(:otlp, installation_id) do
    encode([
      {"resourceMetrics", [[{"resource", resource(installation_id)}, {"scopeMetrics", []}]]}
    ])
  end

  defp build(:json, installation_id, day, counts) do
    [
      {"schema", "rescord.usage/1"},
      {"installation", installation_id},
      {"rescord", Rescord.version()},
      {"day", Date.to_iso8601(day)},
      {"counts",
       for count <- counts do
         [
           {"feature", Atom.to_string(count.feature)},
           {"kind", Atom.to_string(count.kind)},
           {"item", count.item},
           {"count", count.count}
         ]
       end}
    ]
  end

  defp build(:otlp, installation_id, day, counts) do
    start = day |> DateTime.new!(~T[00:00:00], "Etc/UTC") |> DateTime.to_unix(:nanosecond)

    [
      {"resourceMetrics",
       [
         [
           {"resource", resource(installation_id)},
           {"scopeMetrics",
            [
              [
                {"scope", [{"name", "rescord.usage"}, {"version", Rescord.version()}]},
                {"metrics",
                 [
                   [
                     {"name", "rescord.usage.count"},
                     {"description",
                      "How many times a feature was used on the day, on the whole server"},
                     {"unit", "{use}"},
                     {"sum",
                      [
                        {"aggregationTemporality", 1},
                        {"isMonotonic", true},
                        {"dataPoints", Enum.map(counts, &point(&1, start))}
                      ]}
                   ]
                 ]}
              ]
            ]}
         ]
       ]}
    ]
  end

  defp resource(installation_id) do
    [
      {"attributes",
       [
         attribute("service.name", "rescord"),
         attribute("service.version", Rescord.version()),
         attribute("service.instance.id", installation_id)
       ]}
    ]
  end

  defp point(count, start) do
    [
      {"attributes",
       [
         attribute("feature", Atom.to_string(count.feature)),
         attribute("kind", Atom.to_string(count.kind)),
         attribute("item", count.item)
       ]},
      {"startTimeUnixNano", Integer.to_string(start)},
      {"timeUnixNano", Integer.to_string(start + @nanos_a_day)},
      {"asInt", Integer.to_string(count.count)}
    ]
  end

  defp attribute(key, value), do: [{"key", key}, {"value", [{"stringValue", value}]}]

  # A list of pairs is an object whose keys keep their order. The page
  # shows the text with two spaces of indent, as a send writes it.
  defp encode(document), do: document |> ordered() |> Jason.encode!(pretty: true)

  defp ordered([{key, _value} | _rest] = pairs) when is_binary(key),
    do: Jason.OrderedObject.new(Enum.map(pairs, fn {key, value} -> {key, ordered(value)} end))

  defp ordered(list) when is_list(list), do: Enum.map(list, &ordered/1)
  defp ordered(value), do: value
end
