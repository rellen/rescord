defmodule RescordWeb.Features.SignInTest do
  @moduledoc """
  Signs a person in through a real browser: the form, the email, the link,
  the button, a page of an organisation, and the sign-out.

  `RescordWeb.SignInControllerTest` holds each rule of the sign-in with
  requests. This test holds what only a browser shows: that a person finds
  each control by its words, that the session of the sign-in reaches the
  socket of a LiveView, and that the sign-out link works, which needs the
  script of the page.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.FeatureCase, async: false

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_member, user} = member!(organisation, :member, root)

    # The email of the invitation is not what a test looks at.
    flush_emails()

    {:ok, organisation: organisation, address: to_string(user.email)}
  end

  # Asks for a link on the sign-in page, as a person does.
  defp ask_for_link(session, address) do
    session
    |> visit(~p"/sign-in")
    |> fill_in("Email address", with: address)
    |> click_button("Send me a link")
    |> assert_has("h1", text: "Look in your email")
  end

  # The link in the email for an address. The email leaves from a task, so
  # the test waits for the tasks first.
  defp link_in_email(address) do
    wait_for_sign_in_tasks()
    assert_receive {:email, %Swoosh.Email{to: [{_name, ^address}]} = email}, 1_000

    [link] = Regex.run(~r{http\S+/sign-in/link\?token=\S+}, email.text_body)
    link
  end

  test "a member signs in with the link of an email, opens the organisation, and signs out",
       %{conn: session, organisation: organisation, address: address} do
    ask_for_link(session, address)
    link = link_in_email(address)

    # The page of the link does not sign the person in. The button does.
    session
    |> visit(link)
    |> assert_has("h1", text: "Sign in to Rescord")
    |> assert_has("nav a", text: "Sign in")
    |> refute_has("nav a", text: "Sign out")
    |> click_button("Sign in")
    |> assert_path(~p"/")
    |> assert_has("hgroup p", text: "You are signed in as #{address}.")
    |> assert_has("nav span", text: address)

    # The page of the organisation is a LiveView. Its socket has the session.
    session
    |> click_link("main a", "Wattle Creek")
    |> assert_path(~p"/o/#{organisation.short_name}")
    |> assert_connected()
    |> assert_has("h1", text: "Wattle Creek")
    |> assert_has("main", text: "Your role in this organisation: Member.")

    session
    |> click_link("Sign out")
    |> assert_path(~p"/sign-in")
    |> assert_has("nav a", text: "Sign in")
    |> refute_has("nav a", text: "Sign out")

    # After the sign-out, the page of the organisation does not open.
    session
    |> visit(~p"/o/#{organisation.short_name}")
    |> assert_path(~p"/")
    |> assert_has("hgroup p", text: "Sign in to go on.")
  end

  test "an address with no user gets the same page, and no email", %{conn: session} do
    ask_for_link(session, unique_address())

    wait_for_sign_in_tasks()
    refute_receive {:email, _email}, 200
  end

  # The browser writes the status 422 of the second try to its console, and
  # that goes to the log. It is what the test asks for.
  @tag :capture_log
  test "a link works one time", %{conn: session, address: address} do
    ask_for_link(session, address)
    link = link_in_email(address)

    session
    |> visit(link)
    |> click_button("Sign in")
    |> assert_has("hgroup p", text: "You are signed in as #{address}.")
    |> click_link("Sign out")
    |> assert_path(~p"/sign-in")

    session
    |> visit(link)
    |> click_button("Sign in")
    |> assert_has("h1", text: "This link does not work")
    |> assert_has("nav a", text: "Sign in")
    |> click_link("Ask for a new link")
    |> assert_path(~p"/sign-in")
  end
end
