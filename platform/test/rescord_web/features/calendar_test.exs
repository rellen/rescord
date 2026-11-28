defmodule RescordWeb.Features.CalendarTest do
  @moduledoc """
  Holds the page of the calendar feeds in a real browser, on a phone
  (ADR 0074 and ADR 0061): a member makes a feed, reads its address one
  time, and copies it with the button; the long address makes nothing
  wider than the screen; and the address reads the feed.

  The test creates an organisation, so it does not run beside others (see
  `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.FeatureCase, async: false

  alias Rescord.{Accounts, Tasks}

  # An address of its own: an address gets 5 sign-in links in 15 minutes.
  @address "a.member.with.a.calendar@wattle-creek-refuge.example.org"

  @small [viewport: %{width: 320, height: 640}, has_touch: true]

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek Small Animal Refuge")
    {_, administrator} = member!(organisation, :administrator, root)
    {_member, _user} = member!(organisation, :member, administrator, @address)

    {:ok, due_at} =
      Accounts.local_instant(
        organisation,
        "#{Date.to_iso8601(Accounts.today(organisation))}T23:30"
      )

    Tasks.plan_task!(%{title: "Give the herd its evening hay", due_at: due_at},
      actor: administrator,
      tenant: organisation
    )

    # The email of the invitation is not what the test looks at.
    flush_emails()

    {:ok, organisation: organisation, page: "/o/#{organisation.short_name}/calendar"}
  end

  @tag browser_context_opts: @small
  test "a member makes a feed on a phone, and copies its address",
       %{conn: session, page: page, organisation: organisation} do
    session =
      session
      |> sign_in_with_link(@address)
      |> visit(page)
      |> assert_connected()
      |> assert_has("h1", text: "Calendar feeds")
      |> assert_has("#no-feeds")
      |> fill_in("Name, as your calendar app shows it", with: "My phone")
      |> select("Tasks", option: "Each task")
      |> check("The expiry dates of the stock")
      |> click_button("Make the feed")
      |> assert_has("#new-address h2", text: "The address of My phone")
      |> assert_has("#own-feeds strong", text: "My phone")
      # The long address makes nothing wider than the screen.
      |> evaluate(
        "document.documentElement.scrollWidth - document.documentElement.clientWidth",
        fn wider -> assert wider == 0, "the page is #{wider}px wider than the screen" end
      )
      # The button is as high as a finger.
      |> evaluate(
        "document.querySelector('button[data-copy]').getBoundingClientRect().height",
        fn height -> assert height >= 43.5, "the button that copies is #{height}px high" end
      )
      |> click_button("Copy the address")
      # The script selects the address, and says what happened.
      |> evaluate(
        """
        (() => {
          const field = document.querySelector("#feed-address");
          return field.selectionEnd - field.selectionStart === field.value.length;
        })()
        """,
        fn selected -> assert selected, "the button did not select the address" end
      )
      |> assert_has("#feed-address-copied:not(:empty)")

    # The address that the page shows reads the feed, with no session.
    evaluate(
      session,
      """
      (async () => {
        const address = document.querySelector("#feed-address").value;
        const answer = await fetch(address, {credentials: "omit"});
        return {address: address, status: answer.status, type: answer.headers.get("content-type"), body: await answer.text()};
      })()
      """,
      fn answer ->
        assert answer["address"] =~ "/o/#{organisation.short_name}/calendar.ics?token="
        assert answer["status"] == 200
        assert answer["type"] == "text/calendar; charset=utf-8"
        assert answer["body"] =~ "SUMMARY:Give the herd its evening hay"
      end
    )
  end
end
