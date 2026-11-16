defmodule RescordWeb.Features.RoutinesTest do
  @moduledoc """
  Starts a routine through a real browser.

  `RescordWeb.RoutinePagesTest` holds each rule of the page. This test holds
  what only a browser shows: the form of a routine is in a part of the page
  that is closed at first, and it stays open, with what the member typed,
  while the page draws the fields of the pattern that the member chooses,
  and when the page says what is wrong.

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

    {:ok, address: to_string(user.email), path: "/o/#{organisation.short_name}/routines"}
  end

  test "a member starts a routine on two days of the week, and the form stays open as it changes",
       %{conn: session, address: address, path: path} do
    session
    |> sign_in_with_link(address)
    |> visit(path)
    |> assert_connected()
    |> click("summary", "New routine")
    |> fill_in("What to do", with: "Weigh each resident")
    |> select("How it repeats", option: "On given days of the week")
    # The page drew the days of the week, and the form is still open with
    # the words of the member.
    |> assert_has("#routine-weekdays legend", text: "Days of the week")
    |> evaluate("document.getElementById('new-routine').open", fn open -> assert open end)
    |> evaluate("document.getElementById('routine_title').value", fn value ->
      assert value == "Weigh each resident"
    end)
    # A refusal keeps the form open, and says what is wrong in the form.
    |> click_button("Start the routine")
    |> assert_has("#routine p[role=alert]", text: "Weekdays needs one day of the week or more")
    |> evaluate("document.getElementById('new-routine').open", fn open -> assert open end)
    |> check("Monday")
    |> check("Thursday")
    |> fill_in("Time", with: "09:00")
    |> click_button("Start the routine")
    |> assert_has("tbody td", text: "Each Monday and Thursday, at 09:00")
    |> assert_has("[data-state=ok]", text: "Active")
  end
end
