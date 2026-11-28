defmodule RescordWeb.Features.RubyTest do
  @moduledoc """
  A conversation with Ruby in a real browser, on the screen of a small
  phone (ADR 0069 and ADR 0023): a member presses a thing to ask, sees the
  question and "is working", and reads the answer when the job has
  written it; then Enter, on a keyboard with a mouse, sends the next
  question from the field.

  The job of a reply runs in the test process, with the scripted model.
  No test calls a provider.

  The test creates an organisation, so it does not run beside others. Its
  member has an address of its own: an address gets a few sign-in links
  in a quarter of an hour.
  """

  use RescordWeb.FeatureCase, async: false

  import Rescord.RubyFixtures

  alias Rescord.Ruby.ScriptedModel

  @address "a.member.who.asks.ruby@wattle-creek.example.org"

  @small [viewport: %{width: 320, height: 640}, has_touch: true]

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root, @address)
    ruby_on!(root, actor: administrator, tenant: organisation)

    # The email of the invitation is not what the test looks at.
    flush_emails()

    {:ok, ruby: "/o/#{organisation.short_name}/ruby"}
  end

  defp work!, do: Oban.drain_queue(queue: :ruby, with_safety: false)

  @tag browser_context_opts: @small
  test "a member asks a thing on a phone, and reads the answer", %{conn: session, ruby: ruby} do
    session =
      session
      |> sign_in_with_link(@address)
      |> visit(ruby)
      |> assert_has("h1", text: "Ruby")
      |> assert_connected()
      |> click_button("Who is on medication today?")
      |> assert_has("article[data-from=member]", text: "Who is on medication today?")
      |> assert_has("#ruby-answer", text: "is working")
      |> assert_has("button", text: "Stop")

    ScriptedModel.script([{:text, "Two residents are on **medication** today."}])
    work!()

    session
    |> assert_has("article[data-from=ruby] strong", text: "medication")
    |> refute_has("#ruby-answer")
    |> assert_has("button", text: "Send")
    |> assert_has("[role=status]", text: "Ruby answered.")
  end

  test "Enter sends from the field on a keyboard with a mouse, and Shift+Enter does not",
       %{conn: session, ruby: ruby} do
    session
    |> sign_in_with_link(@address)
    |> visit(ruby)
    |> assert_connected()
    |> fill_in("Message to Ruby", with: "Who arrived this week?")
    |> press("#ruby-message", "Shift+Enter")
    |> refute_has("article[data-from=member]")
    |> press("#ruby-message", "Enter")
    |> assert_has("article[data-from=member]", text: "Who arrived this week?")
    |> assert_has("#ruby-answer", text: "is working")
  end
end
