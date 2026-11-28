defmodule RescordWeb.UsageTest do
  @moduledoc """
  The pages and the files of the usage counts (ADR 0098): each page and
  each route maps to a feature of the list, or is left out with a reason,
  so that a count never has a key that a browser sent.
  """

  use ExUnit.Case, async: true

  alias Rescord.Usage.Features
  alias RescordWeb.Usage

  test "each page has a feature of the list" do
    pages =
      for module <- Application.spec(:rescord, :modules),
          Code.ensure_loaded?(module),
          # A page of the code, not of the support of the tests.
          module.module_info(:compile)[:source] |> to_string() =~ "/lib/rescord_web/",
          function_exported?(module, :__live__, 0),
          do: module

    assert pages != []

    for page <- pages do
      assert Features.feature?(Usage.pages()[page]),
             "The page #{inspect(page)} has no feature in RescordWeb.Usage"
    end
  end

  test "each feature of a page or a file is a key of the list" do
    for feature <- Map.values(Usage.pages()), do: assert(Features.feature?(feature))
    for {feature, _item} <- Map.values(Usage.files()), do: assert(Features.feature?(feature))
  end

  test "each route of a controller is counted as a file, or left out with a reason" do
    for %{plug: plug, plug_opts: action} <- Phoenix.Router.routes(RescordWeb.Router),
        plug != Phoenix.LiveView.Plug,
        not String.starts_with?(inspect(plug), "Phoenix.LiveDashboard"),
        plug != Plug.Swoosh.MailboxPreview do
      assert Map.has_key?(Usage.files(), {plug, action}) or
               Map.has_key?(Usage.not_counted(), plug),
             "The route #{inspect(plug)} #{inspect(action)} is not in RescordWeb.Usage"
    end
  end

  test "each file that the list names has a route" do
    routes =
      for %{plug: plug, plug_opts: action} <- Phoenix.Router.routes(RescordWeb.Router),
          do: {plug, action}

    for key <- Map.keys(Usage.files()) do
      assert key in routes, "#{inspect(key)} is no route"
    end
  end

  test "the item of a page is the name of its module" do
    assert Usage.item(RescordWeb.ExpenseFormLive) == "expense_form"
    assert Usage.item(RescordWeb.RootUsageLive) == "root_usage"
  end
end
