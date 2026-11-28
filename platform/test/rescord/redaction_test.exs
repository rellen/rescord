defmodule Rescord.RedactionTest do
  @moduledoc """
  Holds that only an erasure on request changes old versions (ADR 0105,
  issue 31, call 17): the paper trail is never changed, and
  `Rescord.Redaction` is the one exception. A new caller in `lib/` makes
  this test fail, so that the change is a decision and not an accident.
  """

  use ExUnit.Case, async: true

  @callers MapSet.new([
             "lib/rescord/privacy.ex",
             "lib/rescord/calendars/changes/forget_name.ex"
           ])

  test "only an erasure calls the redaction of versions" do
    callers =
      for path <- Path.wildcard("lib/**/*.ex"),
          path != "lib/rescord/redaction.ex",
          File.read!(path) =~ ~r/\bRedaction\.redact_versions\b|Rescord\.Redaction\b(?!,)/,
          into: MapSet.new(),
          do: path

    # `lib/rescord.ex` exports the module from the boundary, and calls nothing.
    assert MapSet.delete(callers, "lib/rescord.ex") == @callers
  end
end
