defmodule RescordWeb.Features.ToolsTest do
  @moduledoc """
  The dose calculator in a real browser, on the screen of a small phone
  (ADR 0072 and ADR 0023): a person finds each field by its words, the
  answer comes into the screen below the form, a change to a field takes
  the answer away, and a number with a comma is refused with words.

  The test creates an organisation, so it does not run beside others (see
  `Rescord.Accounts.OrganisationTest`). Its member has an address of its
  own: an address gets a few sign-in links in a quarter of an hour.
  """

  use RescordWeb.FeatureCase, async: false

  @address "a.member.who.calculates@wattle-creek.example.org"

  @small [viewport: %{width: 320, height: 640}, has_touch: true]

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    member!(organisation, :member, root, @address)

    # The email of the invitation is not what the test looks at.
    flush_emails()

    {:ok, tools: "/o/#{organisation.short_name}/tools"}
  end

  # Whether the whole of an element is in the screen, below the site bar.
  defp in_screen(selector) do
    """
    (async () => {
      await new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)));
      const box = document.querySelector(#{inspect(selector)}).getBoundingClientRect();
      const bar = document.querySelector("header").getBoundingClientRect().bottom;
      return box.top >= bar && box.bottom <= window.innerHeight;
    })()
    """
  end

  @tag browser_context_opts: @small
  test "a member calculates a volume on a phone, and sees the answer and its working",
       %{conn: session, tools: tools} do
    session
    |> sign_in_with_link(@address)
    |> visit(tools)
    |> click_link("Dose calculator")
    |> assert_has("h1", text: "Dose calculator")
    |> assert_connected()
    |> assert_has("aside h2", text: "Check with your vet")
    |> assert_has("output", text: "No result yet")
    |> fill_in("Weight", with: "1095")
    |> select("Unit of the body weight", option: "g", exact: true)
    |> fill_in("Dose", with: "0.2", exact: true)
    |> fill_in("Amount", with: "1.5", exact: true)
    |> click_button("Calculate")
    |> assert_has("output strong", text: "0.146 mL")
    |> assert_has("output", text: "which holds a dose of 0.219 mg")
    |> assert_has("ol[data-working] li", text: "1,095 g = 1.095 kg")
    |> assert_has("ol[data-working] li", text: "0.219 mg ÷ 1.5 mg/mL = 0.146 mL")
    # The answer is below the form, and the page brings it into the screen.
    |> evaluate(in_screen("output"), fn in_screen? ->
      assert in_screen?, "the answer is outside the screen of a phone"
    end)
    # Another number takes the answer away until the next press.
    |> fill_in("Weight", with: "1100")
    |> assert_has("output", text: "No result yet")
    |> refute_has("ol[data-working]")
    |> click_button("Calculate")
    |> assert_has("output strong", text: "0.147 mL")
    # A dose rate in mL takes no strength.
    |> select("Unit of the dose rate", option: "mL", exact: true)
    |> refute_has("#dose_strength")
    |> click_button("Calculate")
    |> assert_has("output strong", text: "0.22 mL")
    |> assert_has("output", text: "is the dose")
  end

  @tag browser_context_opts: @small
  test "a number with a comma is refused, with words beside the field",
       %{conn: session, tools: tools} do
    session
    |> sign_in_with_link(@address)
    |> visit("#{tools}/dose")
    |> assert_connected()
    |> fill_in("Weight", with: "1,095")
    |> fill_in("Dose", with: "0.2", exact: true)
    |> click_button("Calculate")
    |> assert_has("#dose_weight[aria-invalid=true]")
    |> assert_has("#dose_weight-error", text: "no comma")
    |> assert_has("form p[role=alert]", text: "There is no result yet")
    |> assert_has("output", text: "No result yet")
    |> fill_in("Weight", with: "1095")
    |> refute_has("#dose_weight-error")
  end
end
