defmodule Rescord.UsageFixtures do
  @moduledoc """
  Helpers for the tests of the usage counts (ADR 0098): a server that
  sends, with a token, and a count of each kind on the day before.
  """

  # Test support may use any boundary, and any test may use it (ADR 0009).
  use Boundary, top_level?: true, check: [in: false, out: false]

  alias Rescord.Usage

  @doc "Settings that send to a long address, with a token, and three counts."
  def usage!(root) do
    {:ok, _settings} =
      Usage.save_settings(
        %{
          mode: :send,
          endpoint: "https://collector.a-long-name-of-a-server.example.org/v1/metrics"
        },
        actor: root
      )

    {:ok, _settings} = Usage.save_token("a-token-of-the-collector", actor: root)
    yesterday = Date.add(Date.utc_today(), -1)

    for {feature, kind, item, number} <- [
          {:residents, :page, "residents", 31},
          {:expenses, :action, "expenses.expense.approve", 4},
          {:reports, :file, "reports.resident_record", 2}
        ] do
      Usage.add_count!(yesterday, feature, kind, item, number, authorize?: false)
    end

    :ok
  end
end
