defmodule RescordWeb.Features.ResidentsTest do
  @moduledoc """
  Records a resident through a real browser: the form, the page of the
  resident, an absence, and the list.

  `RescordWeb.ResidentPagesTest` holds each rule of the pages. This test
  holds what only a browser shows: that a person finds each field by its
  label, that a form which is closed at first opens with a press, and that a
  page which opens again after a write shows the new state.

  The test creates an organisation, so it does not run beside others (see
  `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.FeatureCase, async: false

  import Rescord.ResidentsFixtures

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_member, user} = member!(organisation, :member, root)
    lists!(organisation, root)

    # The email of the invitation is not what the test looks at.
    flush_emails()

    {:ok, organisation: organisation, address: to_string(user.email)}
  end

  test "a member records a guinea pig, marks it as away, and finds it in the list",
       %{conn: session, organisation: organisation, address: address} do
    base = "/o/#{organisation.short_name}"

    session
    |> sign_in_with_link(address)
    |> click_link("main a", "Wattle Creek")
    |> assert_connected()
    |> click_link("See the residents")
    |> assert_path(base <> "/residents")
    |> assert_connected()
    |> click_link("New resident")
    |> assert_path(base <> "/residents/new")
    |> assert_connected()
    |> fill_in("Name", with: "Biscuit")
    |> select("Species", option: "Guinea pig")
    |> select("Sex", option: "Male")
    |> fill_in("Date of birth", with: "2025-03-01")
    |> check("The date of birth is an estimate")
    |> check("Abyssinian")
    |> check("White")
    |> select("How the resident came", option: "Stray")
    |> fill_in("Date of the arrival", with: Date.to_iso8601(Date.utc_today()))
    |> click_button("Record the resident")
    |> assert_has("h1", text: "Biscuit")
    |> assert_connected()
    |> assert_has("[data-state=ok]", text: "In care")
    |> assert_has("dd", text: "About 1 March 2025")
    |> assert_has("dd", text: "Abyssinian")
    |> assert_has("dd", text: "Stray")

    # The form of an absence is closed until the person opens it.
    session
    |> click("summary", "Mark as away for a time")
    |> fill_in("Where and why", with: "At the clinic")
    |> click_button("Mark as away")
    |> assert_has("[data-state=info]", text: "Away for a time")
    |> assert_has("dd", text: "At the clinic")
    |> assert_connected()

    session
    |> click_link("nav[aria-label=Breadcrumb] a", "Residents")
    |> assert_path(base <> "/residents")
    |> assert_has("tbody tr", text: "Biscuit")
    |> assert_has("tbody [data-state=info]", text: "Away for a time")
  end
end
