defmodule RescordWeb.Features.RolesSpikeTest do
  @moduledoc "Spike: the locators of RescordWeb.Roles in a browser."

  use RescordWeb.FeatureCase, async: false
  use RescordWeb.Roles, browser: true

  @address "a.member.who.spikes@wattle-creek.example.org"

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    member!(organisation, :member, root, @address)
    flush_emails()
    {:ok, tools: "/o/#{organisation.short_name}/tools"}
  end

  test "landmarks, headings and names in a browser", %{conn: session, tools: tools} do
    session
    |> sign_in_with_link(@address)
    |> visit(tools)
    |> click(main() |> link("Dose calculator"))
    |> assert_has(main() |> heading(level: 1), text: "Dose calculator")
    |> assert_connected()
    |> assert_has(complementary("Check with your vet"))
    |> assert_has(main() |> status(), text: "No result yet")
    |> refute_has(main() |> button("Nothing of the kind"))
    |> assert_has(banner() |> navigation("Site"))
    |> within(main(), fn session ->
      session
      |> fill_in("Weight", with: "1095")
      |> click(button("Calculate"))
    end)
    |> assert_has(main() |> heading(~r/Calculator|calculator/))
  end
end
