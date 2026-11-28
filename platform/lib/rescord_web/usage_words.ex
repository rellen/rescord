defmodule RescordWeb.UsageWords do
  @moduledoc """
  The words of the usage counts (ADR 0098): the name of each feature, the
  modes and the formats, and what a send found.
  """

  @features %{
    organisation: "The first page of an organisation",
    residents: "Residents",
    groups: "Families and groups",
    housing: "Housing",
    journal: "The journal",
    conditions: "Conditions",
    measurements: "Measurements",
    timeline: "The timeline",
    photos: "Photos",
    tasks: "Tasks",
    routines: "Routines",
    calendar: "The calendar",
    inventory: "The inventory",
    expenses: "Expenses",
    reports: "Reports",
    transfers: "Transfers",
    export: "The export",
    tools: "Tools",
    assistant: "The assistant",
    lists: "The lists",
    members: "Members and roles",
    settings: "The settings of an organisation",
    server: "The pages of the server"
  }

  @doc "The name of a feature."
  @spec feature(atom) :: String.t()
  def feature(feature), do: Map.get(@features, feature, to_string(feature))

  @doc "The modes, with a sentence each, in the order of the form."
  @spec modes() :: [{atom, String.t(), String.t()}]
  def modes do
    [
      {:local, "Count on this server",
       "Rescord counts, and shows the counts here. Nothing leaves the server."},
      {:send, "Count, and send each day",
       "Rescord also sends the counts of each full day to the address below."},
      {:off, "Count nothing",
       "Rescord stores no new count. The counts that are here stay until they are too old, or until you delete them."}
    ]
  end

  @doc "The mode, in a few words."
  @spec mode(atom) :: String.t()
  def mode(:local), do: "Counted on this server, and sent nowhere"
  def mode(:send), do: "Counted, and sent each day"
  def mode(:off), do: "Not counted"

  @doc "The formats, with a sentence each."
  @spec formats() :: [{atom, String.t(), String.t()}]
  def formats do
    [
      {:otlp, "OpenTelemetry (OTLP, JSON over HTTP)",
       "For an OpenTelemetry Collector or another OTLP receiver. Give its address with /v1/metrics."},
      {:json, "The plain document of Rescord",
       "One JSON document for each day, for any service that takes one."}
    ]
  end

  @doc "The name of a format."
  @spec format(atom) :: String.t()
  def format(:otlp), do: "OpenTelemetry (OTLP)"
  def format(:json), do: "The plain document of Rescord"

  @doc "What a send or a test found, as `{kind of state, words}`."
  @spec result(atom | nil, integer | nil) :: {String.t(), String.t()}
  def result(nil, _status), do: {"none", "Nothing sent yet"}
  def result(:ok, status), do: {"ok", "The address took it (#{status})"}
  def result(:status, status), do: {"alert", "The address answered #{status}"}
  def result(:unreachable, _status), do: {"alert", "No answer from the address"}

  def result(:sealed, _status),
    do: {"alert", "This server cannot open the token: type it again"}

  @doc "The token, as the page shows it: never the token itself."
  @spec token(map) :: String.t()
  def token(%{token_set_at: nil}), do: "No token"
  def token(%{token_hint: nil, token_set_at: set_at}), do: "Set on #{day(set_at)}"

  def token(%{token_hint: hint, token_set_at: set_at}),
    do: "Ends in #{hint}, set on #{day(set_at)}"

  @doc "A day, such as 27 November 2026."
  @spec day(Date.t() | DateTime.t() | nil) :: String.t()
  def day(nil), do: "never"
  def day(%DateTime{} = time), do: time |> DateTime.to_date() |> day()
  def day(%Date{} = date), do: Calendar.strftime(date, "%-d %B %Y")

  @doc "A time in UTC, such as 27 November 2026, 14:05 UTC."
  @spec time(DateTime.t() | nil) :: String.t()
  def time(nil), do: "never"
  def time(%DateTime{} = time), do: Calendar.strftime(time, "%-d %B %Y, %H:%M UTC")
end
