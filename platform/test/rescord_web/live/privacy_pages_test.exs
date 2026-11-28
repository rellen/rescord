defmodule RescordWeb.PrivacyPagesTest do
  @moduledoc """
  Holds the pages of privacy (ADR 0105): a member asks for the erasure of
  their data, an administrator records a request, erases from it, extends
  or refuses one, and keeps the settings; a member sees only their own
  requests; only a root user erases an administrator.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures
  import Rescord.StorageFixtures

  alias Rescord.{Accounts, Privacy}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    disk_store!(tmp_dir)
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {member_row, member} = member!(organisation, :member, administrator)
    send_invitations()

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     member_row: member_row,
     path: ~p"/o/#{organisation.short_name}/privacy"}
  end

  defp open(conn, user, path) do
    {:ok, view, _html} = conn |> sign_in(user) |> live(path)
    {view, render_async(view)}
  end

  test "a member asks for the erasure of their data, and sees only their own requests", context do
    {view, html} = open(context.conn, context.member, context.path)

    assert html =~ "Your data"
    refute html =~ "Requests that wait"
    refute html =~ "Record a request"

    view |> element("#ask") |> render_click()

    assert has_element?(view, "#own-requests tbody tr")
    refute has_element?(view, "#ask")

    {:ok, [request]} = Privacy.requests(tenant: context.organisation, authorize?: false)
    assert request.user_id == context.member.id
    assert request.how_received == :own_page
    assert request.due_on == Date.shift(Accounts.today(context.organisation), month: 1)
  end

  test "an administrator records a request, and erases from it", context do
    path = context.path <> "?member=#{context.member_row.id}"
    {view, html} = open(context.conn, context.administrator, path)

    assert html =~ "No request waits."

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> form("#record", %{
               "request" => %{
                 "member_id" => context.member_row.id,
                 "how_received" => "email",
                 "identity" => "Answered from the address of the account",
                 "received_on" => Date.to_iso8601(Accounts.today(context.organisation))
               }
             })
             |> render_submit()

    {:ok, view, html} = context.conn |> sign_in(context.administrator) |> live(to)
    assert html =~ "What goes"
    assert html =~ "No money record needs their email."

    # The box must be ticked.
    view |> form("#erase", %{"erase" => %{"kept" => ""}}) |> render_submit()
    assert render(view) =~ "Tick the box"

    view
    |> form("#erase", %{"erase" => %{"comments" => "delete", "kept" => "", "sure" => "true"}})
    |> render_submit()

    assert render(view) =~ "Former member 1"
    refute has_element?(view, "#erase")

    assert Accounts.labels(actor: context.administrator, tenant: context.organisation)[
             context.member.id
           ] ==
             "Former member 1"
  end

  test "an administrator extends and refuses a request", context do
    {:ok, request} =
      Privacy.record_request(
        %{member_id: context.member_row.id, how_received: :letter, identity: "Signed letter"},
        actor: context.administrator,
        tenant: context.organisation
      )

    {view, _html} = open(context.conn, context.administrator, context.path <> "/#{request.id}")
    today = Accounts.today(context.organisation)

    view
    |> form("#extend-form", %{
      "extend" => %{
        "extended_to" => Date.to_iso8601(Date.shift(request.due_on, month: 3)),
        "extension_reason" => "Many requests",
        "told_of_extension_on" => Date.to_iso8601(today)
      }
    })
    |> render_submit()

    assert render(view) =~ "more than two months"

    view
    |> form("#extend-form", %{
      "extend" => %{
        "extended_to" => Date.to_iso8601(Date.shift(request.due_on, month: 1)),
        "extension_reason" => "Many requests",
        "told_of_extension_on" => Date.to_iso8601(today)
      }
    })
    |> render_submit()

    assert render(view) =~ "Many requests"

    view
    |> form("#refuse-form", %{"refuse" => %{"refusal_reason" => "Manifestly unfounded"}})
    |> render_submit()

    assert render(view) =~ "Refused"
    refute has_element?(view, "#erase")
  end

  test "only a root user erases an administrator", context do
    {admin_row, _other} = member!(context.organisation, :administrator, context.root)

    {:ok, request} =
      Privacy.record_request(
        %{member_id: admin_row.id, how_received: :email, identity: "By email"},
        actor: context.administrator,
        tenant: context.organisation
      )

    path = context.path <> "/#{request.id}"
    {_view, html} = open(context.conn, context.administrator, path)
    assert html =~ "Only a root user erases"
    refute html =~ "Erase the data"

    {_view, html} = open(context.conn, context.root, path)
    assert html =~ "Erase the data"
  end

  test "an administrator saves the settings of privacy", context do
    {view, _html} = open(context.conn, context.administrator, context.path)

    view
    |> form("#settings", %{
      "settings" => %{
        "money_years" => "5",
        "pseudonymise_after_months" => "",
        "closed_request_years" => "3",
        "contact_name" => "Jo",
        "contact_email" => "privacy@example.org",
        "authority" => "OAIC",
        "notice_text" => ""
      }
    })
    |> render_submit()

    assert render(view) =~ "The settings of privacy are saved."
    assert Privacy.settings(context.organisation).money_years == 5
  end

  test "the members page links each member to a request to erase, for an administrator",
       context do
    {view, _html} =
      open(context.conn, context.administrator, ~p"/o/#{context.organisation.short_name}/members")

    assert has_element?(view, ~s(a[href$="privacy?member=#{context.member_row.id}"]))

    {view, _html} =
      open(context.conn, context.member, ~p"/o/#{context.organisation.short_name}/members")

    refute has_element?(view, ~s(a[href*="privacy?member="]))
  end
end
