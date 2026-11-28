defmodule RescordWeb.Features.JournalTest do
  @moduledoc """
  Writes a journal entry through a real browser.

  `RescordWeb.JournalPagesTest` holds each rule of the page. This test holds
  what only a browser shows: the form of an entry is in a part of the page
  that is closed at first, and it stays open while the page draws the
  fields of the kind that the member chooses, and when the page says what
  is wrong. Without `keepDetailsOpen` of `shoddy_phoenix` each new render
  closes it.

  The test creates an organisation, so it does not run beside others (see
  `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.FeatureCase, async: false

  import Rescord.ResidentsFixtures

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_member, user} = member!(organisation, :member, root)
    lists = lists!(organisation, root)
    biscuit = resident!(lists, actor: root, tenant: organisation)

    # The email of the invitation is not what the test looks at.
    flush_emails()

    {:ok,
     address: to_string(user.email),
     path: "/o/#{organisation.short_name}/residents/#{biscuit.id}/journal"}
  end

  test "a member records a weight, and the form stays open while its fields change",
       %{conn: session, address: address, path: path} do
    session
    |> sign_in_with_link(address)
    |> visit(path)
    |> assert_connected()
    |> click("summary", "New journal entry")
    |> select("Kind", option: "Measurement")
    # The page drew the fields of a measurement, and the form is still open.
    |> select("What was measured", option: "Weight")
    |> fill_in("Value", with: "1095")
    |> select("Unit", option: "g")
    |> click_button("Write the entry")
    |> assert_has("article p", text: "Weight: 1,095 g")
    |> assert_connected()

    # A refusal keeps the form open, with what the member typed.
    session
    |> click("summary", "New journal entry")
    |> select("Kind", option: "Vaccination")
    |> fill_in("Note", with: "Given in the left leg.")
    |> evaluate("document.querySelector('#entry [name=\"entry[vaccine]\"]').required = false")
    |> click_button("Write the entry")
    |> assert_has("main p[role=alert]", text: "Vaccine is required")
    # The words of a text area are its value, and not its text.
    |> evaluate("document.querySelector('#entry textarea').value", fn value ->
      assert value == "Given in the left leg."
    end)
    |> fill_in("Vaccine", with: "A sample vaccine")
    |> click_button("Write the entry")
    |> assert_has("article p", text: "Vaccine: A sample vaccine")
  end
end
