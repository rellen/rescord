defmodule RescordWeb.Features.CollectionsTest do
  @moduledoc """
  Uses the controls of a collection of Cinder in a real browser, with the
  keyboard, and reads what they say to a screen reader (ADR 0017 and
  ADR 0087).

  `RescordWeb.CinderTest` holds the selectors of `cinder_tables.ts` to the
  markup of Cinder. This test holds what only a browser shows: that the
  button of a choice filter follows its list, that the arrow keys keep the
  list open and the focus in it, that Enter and Escape give the focus back
  to the button, and that the status region says a new result.

  The test creates an organisation, so it does not run beside others (see
  `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.FeatureCase, async: false

  import Rescord.ResidentsFixtures

  @button "#residents-filter-sex-button"
  @list "#residents-filter-sex-options"

  # Where the focus is: the id of the element, or the value of a choice.
  @focus """
  (() => {
    const active = document.activeElement;
    return active.id || active.value || active.tagName;
  })()
  """

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_member, user} = member!(organisation, :member, root)
    lists = lists!(organisation, root)
    options = [actor: root, tenant: organisation]

    # More residents than one page holds, and one female among them.
    for number <- 1..26, do: resident!(lists, options, %{name: "Resident #{number}"})
    resident!(lists, options, %{name: "Clover", sex: :female})

    # The email of the invitation is not what the test looks at.
    flush_emails()

    {:ok, page: "/o/#{organisation.short_name}/residents", address: to_string(user.email)}
  end

  test "a choice filter says its state and its choice, and works from the keyboard",
       %{conn: session, page: page, address: address} do
    session =
      session
      |> sign_in_with_link(address)
      |> visit(page)
      |> assert_connected()
      |> assert_has("tbody tr", count: 25)

    # The button says the filter, the choice, and that its list is closed.
    session
    |> assert_has(
      ~s|#{@button}[aria-expanded="false"][aria-controls="#{String.trim_leading(@list, "#")}"]|
    )
    |> assert_has(~s|#{@button}[aria-label="Sex: Any sex"]|)

    # Enter opens the list, and the button says so. The list is a group
    # of radio buttons with the name of the filter.
    session
    |> press(@button, "Enter")
    |> assert_has(~s|#{@button}[aria-expanded="true"]|)
    |> assert_has(~s|#{@list}[role="radiogroup"][aria-label="Sex"]|)

    # An arrow key chooses the next choice. The rows follow, the list stays
    # open, and the focus stays on the choice.
    session
    |> press("#{@list} input:checked", "ArrowDown")
    |> assert_has(~s|#{@button}[aria-label="Sex: Female"][aria-expanded="true"]|)
    |> assert_has("tbody tr", count: 1)
    |> assert_has("tbody tr", text: "Clover")
    |> evaluate(@focus, fn focus -> assert focus == "female" end)

    # The status region says the new result.
    assert_has(session, "[data-cinder-status][role=status]", text: "1 result")

    # Enter closes the list, and the focus goes to the button.
    session
    |> press("#{@list} input:checked", "Enter")
    |> assert_has(~s|#{@button}[aria-expanded="false"]|)
    |> evaluate(@focus, fn focus -> assert "#" <> focus == @button end)

    # Escape closes it too.
    session
    |> press(@button, "Enter")
    |> assert_has(~s|#{@button}[aria-expanded="true"]|)
    |> press("#{@list} input:checked", "Escape")
    |> assert_has(~s|#{@button}[aria-expanded="false"]|)
    |> evaluate(@focus, fn focus -> assert "#" <> focus == @button end)

    # The button that clears the filter says which filter, and the one that
    # clears the search says no word twice.
    session
    |> assert_has(~s|button[aria-label="Clear filter: Sex"]|)
    |> fill_in("Search", with: "Clo")
    |> assert_has(~s|button[aria-label="Clear search"]|)
  end

  test "a choice with the mouse closes the list and gives the focus to the button",
       %{conn: session, page: page, address: address} do
    session
    |> sign_in_with_link(address)
    |> visit(page)
    |> assert_connected()
    |> assert_has("tbody tr", count: 25)
    |> click(@button)
    |> assert_has(~s|#{@button}[aria-expanded="true"]|)
    |> click("#{@list} label", "Female")
    |> assert_has(~s|#{@button}[aria-label="Sex: Female"][aria-expanded="false"]|)
    |> assert_has("tbody tr", count: 1)
    |> evaluate(@focus, fn focus -> assert "#" <> focus == @button end)
  end

  test "the table, the pages and the drawings say what they are",
       %{conn: session, page: page, address: address} do
    session =
      session
      |> sign_in_with_link(address)
      |> visit(page)
      |> assert_connected()
      |> assert_has("tbody tr", count: 25)

    # The table has the name of the page, and the pages are a landmark.
    session
    |> assert_has(~s|table[aria-label="Residents"]|)
    |> assert_has(~s|[role="navigation"][aria-label="Pages"] [aria-current="page"]|, text: "1")
    |> assert_has(~s|button[aria-label="Next page"]|)
    |> assert_has(~s|button[aria-label="Show 25 per page"][aria-expanded="false"]|)

    # Nothing is said for the first result of the page.
    session
    |> evaluate(
      ~s|document.querySelector("[data-cinder-status]")?.textContent ?? ""|,
      fn said -> assert said == "" end
    )

    # The next page: the marks are there again, and the region says it.
    session
    |> click(~s|button[title="Next page"]|)
    |> assert_has("tbody tr", count: 2)
    |> assert_has(~s|[role="navigation"][aria-label="Pages"] [aria-current="page"]|, text: "2")
    |> assert_has("[data-cinder-status]", text: "Page 2 of 2")
    |> assert_has(~s|table[aria-label="Residents"]|)

    # No drawing of Cinder is left for a screen reader to read.
    session
    |> evaluate(
      ~s|document.querySelectorAll('[data-key="container_class"] svg:not([aria-hidden="true"])').length|,
      fn count -> assert count == 0 end
    )
  end
end
