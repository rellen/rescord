defmodule RescordWeb.OrganisationPagesTest do
  @moduledoc """
  Holds the pages of the organisations and of the root user: who can open
  each page, and what each role sees and can do on it.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures
  import Swoosh.TestAssertions

  alias Rescord.Accounts

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)

    # The emails of those invitations are not what a test looks at. A job
    # sends each one (ADR 0067), so the jobs run here.
    send_invitations()
    flush_emails()

    {:ok, root: root, organisation: organisation, administrator: administrator, member: member}
  end

  defp flush_emails do
    receive do
      {:email, _email} -> flush_emails()
    after
      0 -> :ok
    end
  end

  defp role_with_key(context, key) do
    {:ok, roles} = Accounts.roles(tenant: context.organisation, authorize?: false)
    Enum.find(roles, &(&1.key == key))
  end

  # The key of the role of the member with an address.
  defp role_key_of(context, address) do
    [member] =
      Accounts.members!(tenant: context.organisation, authorize?: false, load: [:email, :role])
      |> Enum.filter(&(to_string(&1.email) == address))

    member.role.key
  end

  # The rows of the table of a collection, without its filters, which name
  # each choice.
  defp rows(html) do
    html |> LazyHTML.from_fragment() |> LazyHTML.query("tbody") |> LazyHTML.to_html()
  end

  defp open(conn, user, path) do
    {:ok, view, _html} = conn |> sign_in(user) |> live(path)
    {view, render_async(view)}
  end

  describe "the home page" do
    test "lists the organisations of a member, and no link to the root page", context do
      html = context.conn |> sign_in(context.member) |> get(~p"/") |> html_response(200)

      assert html =~ "Wattle Creek"
      assert html =~ ~p"/o/#{context.organisation.short_name}"
      refute html =~ ~s(href="/root")
    end

    test "tells a user with no organisation that they have none", context do
      html = context.conn |> sign_in(user!()) |> get(~p"/") |> html_response(200)

      assert html =~ "You are not a member of an organisation"
      refute html =~ "Wattle Creek"
    end

    test "gives a root user each organisation and the root page", context do
      html = context.conn |> sign_in(context.root) |> get(~p"/") |> html_response(200)

      assert html =~ "Wattle Creek"
      assert html =~ ~s(href="/root")
    end
  end

  describe "the root page" do
    test "opens only for a root user", context do
      for user <- [context.administrator, context.member, user!()] do
        assert {:error, {:redirect, %{to: "/"}}} =
                 context.conn |> sign_in(user) |> live(~p"/root")
      end

      assert {:error, {:redirect, %{to: "/"}}} = live(context.conn, ~p"/root")

      {_view, html} = open(context.conn, context.root, ~p"/root")
      assert html =~ "Wattle Creek"
    end

    test "reads the filter of the organisations from the address (ADR 0084)", context do
      organisation!(context.root, "Ironbark Flat")

      {_view, html} = open(context.conn, context.root, "/root?name=iron")
      assert rows(html) =~ "Ironbark Flat"
      refute rows(html) =~ "Wattle Creek"

      {_view, html} = open(context.conn, context.root, "/root?name=nowhere")
      assert html =~ "No organisation matches the filter."

      # A parameter that names no field changes nothing.
      {_view, html} = open(context.conn, context.root, "/root?colour=tan&page=x")
      assert rows(html) =~ "Wattle Creek"
      assert rows(html) =~ "Ironbark Flat"
    end

    test "says which version of Rescord the server runs", context do
      {_view, html} = open(context.conn, context.root, ~p"/root")
      assert html =~ "This server runs Rescord #{Mix.Project.config()[:version]}."
    end

    test "closes each open page of a user who gets or loses the root grant", context do
      other = root!()
      plain = user!()
      topic = fn user -> RescordWeb.UserAuth.socket_id(user.id) end
      RescordWeb.Endpoint.subscribe(topic.(other))
      RescordWeb.Endpoint.subscribe(topic.(plain))

      {view, _html} = open(context.conn, context.root, ~p"/root")

      # The open pages of a root user who is one no more lose that grant.
      render_click(view, "revoke_root", %{"id" => other.id})
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: topic_other}
      assert topic_other == topic.(other)

      view
      |> form("#new-root", root: %{email: to_string(plain.email)})
      |> render_submit()

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: topic_plain}
      assert topic_plain == topic.(plain)
    end

    test "creates an organisation, and says what is wrong with a short name", context do
      {view, _html} = open(context.conn, context.root, ~p"/root")

      html =
        view
        |> form("#new-organisation",
          organisation: %{
            name: "Banksia",
            short_name: "Banksia Road",
            time_zone: "Australia/Perth"
          }
        )
        |> render_submit()

      assert has_element?(view, "main p[role=alert]")
      assert html =~ "Short name"

      view
      |> form("#new-organisation",
        organisation: %{name: "Banksia", short_name: "banksia-road", time_zone: "Australia/Perth"}
      )
      |> render_submit()

      assert render_async(view) =~ "banksia-road"

      assert {:ok, %{name: "Banksia", time_zone: "Australia/Perth"}} =
               Accounts.organisation_by_short_name("banksia-road", actor: context.root)
    end

    test "offers the time zones, and refuses a zone that is not one", context do
      {view, html} = open(context.conn, context.root, ~p"/root")

      assert html =~ ~s(<option value="Australia/Brisbane">)

      html =
        view
        |> form("#new-organisation",
          organisation: %{name: "Banksia", short_name: "banksia-road", time_zone: "Perth"}
        )
        |> render_submit()

      assert has_element?(view, "main p[role=alert]")
      assert html =~ "Time zone is not a time zone that Rescord knows"
      assert {:ok, nil} = Accounts.organisation_by_short_name("banksia-road", actor: context.root)
    end

    test "offers the languages and regions, with the default chosen, and creates with one",
         context do
      {view, _html} = open(context.conn, context.root, ~p"/root")

      assert has_element?(view, "#new-organisation option[value=en-AU][selected]")

      assert has_element?(
               view,
               "#new-organisation option[value=en-US]",
               "English (United States)"
             )

      view
      |> form("#new-organisation",
        organisation: %{
          name: "Banksia",
          short_name: "banksia-road",
          time_zone: "Australia/Perth",
          locale: "en-NZ"
        }
      )
      |> render_submit()

      assert render_async(view) =~ "banksia-road"

      assert {:ok, %{locale: "en-NZ"}} =
               Accounts.organisation_by_short_name("banksia-road", actor: context.root)

      # A locale that the form did not offer is refused.
      render_submit(view, "create_organisation", %{
        "organisation" => %{
          "name" => "Correa",
          "short_name" => "correa-lane",
          "time_zone" => "Australia/Perth",
          "locale" => "fr"
        }
      })

      assert has_element?(view, "main p[role=alert]", "Locale is not a language and region")
      assert {:ok, nil} = Accounts.organisation_by_short_name("correa-lane", actor: context.root)
    end

    test "makes a user a root user, and says so for an address with no user", context do
      {view, _html} = open(context.conn, context.root, ~p"/root")
      user = user!()

      html = view |> form("#new-root", root: %{email: unique_address()}) |> render_submit()
      assert html =~ "No user has the address"

      html = view |> form("#new-root", root: %{email: to_string(user.email)}) |> render_submit()
      assert html =~ "is a root user now"
      assert length(Accounts.roots!(authorize?: false)) == 2
    end
  end

  describe "the pages of an organisation" do
    test "open for its members and for a root user, with what each one is there", context do
      path = ~p"/o/#{context.organisation.short_name}"

      for {user, words} <- [
            {context.member, "Your role in this organisation: Member."},
            {context.administrator, "Your role in this organisation: Administrator."},
            {context.root, "You are a root user"}
          ] do
        {_view, html} = open(context.conn, user, path)
        assert html =~ "Wattle Creek"
        assert html =~ words
      end
    end

    test "do not open for a user of another organisation, and look like no page", context do
      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)

      for path <- [
            ~p"/o/#{context.organisation.short_name}",
            ~p"/o/#{context.organisation.short_name}/members",
            ~p"/o/no-such-refuge"
          ] do
        assert {:error, {:redirect, %{to: "/"}}} =
                 context.conn |> sign_in(outsider) |> live(path)

        assert {:error, {:redirect, %{to: "/"}}} = live(context.conn, path)
      end
    end
  end

  describe "the settings page" do
    test "shows the time zone to a member, with no form", context do
      path = ~p"/o/#{context.organisation.short_name}/settings"
      {view, html} = open(context.conn, context.member, path)

      assert html =~ "Australia/Brisbane"
      assert html =~ "Today here"
      refute has_element?(view, "#settings")

      # An event that the page did not offer is refused.
      render_submit(view, "save", %{"settings" => %{"time_zone" => "Australia/Perth"}})
      assert has_element?(view, "main p[role=alert]")

      assert Accounts.time_zone_of(Rescord.Accounts.Organisation.schema(context.organisation)) ==
               "Australia/Brisbane"
    end

    test "lets an administrator change the time zone, and says when a zone is not one", context do
      path = ~p"/o/#{context.organisation.short_name}/settings"
      conn = sign_in(context.conn, context.administrator)
      {:ok, view, _html} = live(conn, path)

      html = view |> form("#settings", settings: %{time_zone: "Perth"}) |> render_submit()
      assert has_element?(view, "main p[role=alert]")
      assert html =~ "Time zone is not a time zone that Rescord knows"

      {:ok, view, html} =
        view
        |> form("#settings", settings: %{time_zone: "Australia/Perth"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "The time zone is Australia/Perth now."
      assert has_element?(view, "dd", "Australia/Perth")
    end
  end

  describe "the language and region, on the settings page" do
    test "are English (Australia) at first, and a member reads them with no form", context do
      path = ~p"/o/#{context.organisation.short_name}/settings"
      {view, _html} = open(context.conn, context.member, path)

      assert has_element?(view, "dd", "English (Australia)")
      assert has_element?(view, "dd", "16 November 2026")
      assert has_element?(view, "dd", "6:30 pm")
      assert has_element?(view, "dd", "1,234,567.5")
      refute has_element?(view, "#locale")

      # An event that the page did not offer is refused.
      render_submit(view, "save_locale", %{"locale" => %{"locale" => "en-US"}})
      assert has_element?(view, "main p[role=alert]")

      assert {:ok, %{locale: "en-AU"}} =
               Accounts.organisation_by_short_name(context.organisation.short_name,
                 actor: context.root
               )
    end

    test "an administrator changes them, and the pages have the forms of the new ones",
         context do
      path = ~p"/o/#{context.organisation.short_name}/settings"
      conn = sign_in(context.conn, context.administrator)
      {:ok, view, _html} = live(conn, path)

      assert has_element?(view, "#locale option[value=en-AU][selected]")

      # A locale that the form did not offer is refused.
      render_submit(view, "save_locale", %{"locale" => %{"locale" => "fr"}})
      assert has_element?(view, "main p[role=alert]", "Locale is not a language and region")

      {:ok, view, html} =
        view
        |> form("#locale", locale: %{locale: "en-US"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "The language and region are English (United States) now."
      assert has_element?(view, "dd", "English (United States)")
      assert has_element?(view, "dd", "November 16, 2026")
      assert has_element?(view, "dd", "6:30 PM")
      assert has_element?(view, "#locale option[value=en-US][selected]")

      # The date of today, which is another part of the page, follows too.
      today = Accounts.today(context.organisation)
      assert has_element?(view, "dd", Calendar.strftime(today, "%B %-d, %Y"))

      {:ok, view, _html} =
        view
        |> form("#locale", locale: %{locale: "en-GB"})
        |> render_submit()
        |> follow_redirect(conn)

      assert has_element?(view, "dd", "18:30")
      assert has_element?(view, "dd", Calendar.strftime(today, "%-d %B %Y"))
    end

    test "the pages of another organisation keep the forms of that one", context do
      {:ok, _organisation} =
        Accounts.set_organisation_locale(context.organisation, "en-US", actor: context.root)

      other = organisation!(context.root, "Other")
      {_, person} = member!(other, :member, context.root)

      {view, _html} = open(context.conn, person, ~p"/o/#{other.short_name}/settings")
      assert has_element?(view, "dd", "16 November 2026")

      {view, _html} =
        open(context.conn, context.member, ~p"/o/#{context.organisation.short_name}/settings")

      assert has_element?(view, "dd", "November 16, 2026")
    end
  end

  describe "the days ahead of the tasks, on the settings page" do
    test "are 14 at first, and a member reads them with no form", context do
      path = ~p"/o/#{context.organisation.short_name}/settings"
      {view, _html} = open(context.conn, context.member, path)

      assert has_element?(view, "dd", "14 days ahead")
      refute has_element?(view, "#ahead")

      # An event that the page did not offer is refused.
      render_submit(view, "save_ahead", %{"ahead" => %{"task_days_ahead" => "30"}})
      assert has_element?(view, "main p[role=alert]")
      schema = Rescord.Accounts.Organisation.schema(context.organisation)
      assert Accounts.organisation_of(schema).task_days_ahead == 14
    end

    test "are changed by an administrator, and the routines get their tasks at once", context do
      path = ~p"/o/#{context.organisation.short_name}/settings"
      conn = sign_in(context.conn, context.administrator)
      options = [actor: context.administrator, tenant: context.organisation]
      today = Accounts.today(context.organisation)

      Rescord.Tasks.start_routine!(
        %{title: "Hay", pattern: :daily, times: [~T[08:00:00]], starts_on: today},
        options
      )

      far = Date.add(today, 20)
      assert {:ok, []} = Rescord.Tasks.day(far, options)

      {:ok, view, _html} = live(conn, path)

      html = view |> form("#ahead", ahead: %{task_days_ahead: "0"}) |> render_submit()
      assert has_element?(view, "main p[role=alert]")
      assert html =~ "Task days ahead must be greater than or equal to 1"

      {:ok, view, html} =
        view
        |> form("#ahead", ahead: %{task_days_ahead: "21"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "The tasks of the routines exist 21 days ahead now."
      assert has_element?(view, "dd", "21 days ahead")
      assert {:ok, [%{title: "Hay"}]} = Rescord.Tasks.day(far, options)
    end
  end

  describe "the members page" do
    test "shows the members with their roles to a member, with no form and no button", context do
      {_view, html} =
        open(context.conn, context.member, ~p"/o/#{context.organisation.short_name}/members")

      assert html =~ to_string(context.administrator.email)
      assert html =~ to_string(context.member.email)
      assert html =~ "Administrator"

      refute html =~ "Invite a person"
      refute html =~ "Give the role"
      refute html =~ ~s(phx-click="remove")
    end

    test "reads the search and the filter on the role from the address (ADR 0084)", context do
      members = ~p"/o/#{context.organisation.short_name}/members"
      administrator = to_string(context.administrator.email)
      member = to_string(context.member.email)

      # A part of an address, in any case of its letters.
      part = administrator |> String.split("@") |> hd() |> String.upcase()
      {_view, html} = open(context.conn, context.member, members <> "?search=" <> part)
      assert rows(html) =~ administrator
      refute rows(html) =~ member

      role = role_with_key(context, :member)
      {_view, html} = open(context.conn, context.member, members <> "?role_id=" <> role.id)
      assert rows(html) =~ member
      refute rows(html) =~ administrator

      {_view, html} = open(context.conn, context.member, members <> "?search=nobody-at-all")
      assert html =~ "No member matches the search and the filter."

      # A parameter that names no field, and a role that is not one, change
      # nothing and make no fault.
      {_view, html} = open(context.conn, context.member, members <> "?colour=tan&role_id=x")
      assert rows(html) =~ member
    end

    test "finds no member of another organisation with the search", context do
      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :member, context.root)
      send_invitations()

      {_view, html} =
        open(
          context.conn,
          context.member,
          ~p"/o/#{context.organisation.short_name}/members?search=#{outsider.email}"
        )

      refute html =~ to_string(outsider.email) <> "</"
      assert html =~ "No member matches the search and the filter."
    end

    test "writes the filter on the role into the address", context do
      {view, _html} =
        open(context.conn, context.member, ~p"/o/#{context.organisation.short_name}/members")

      role = role_with_key(context, :member)

      view
      |> element("#members-filter-form")
      |> render_change(%{"filters" => %{"role_id" => role.id}})

      assert assert_patch(view) =~ "role_id=" <> role.id

      rows = view |> render_async() |> rows()
      assert rows =~ to_string(context.member.email)
      refute rows =~ to_string(context.administrator.email)
    end

    test "lets an administrator invite a member, with the role of a member at first", context do
      {view, html} =
        open(
          context.conn,
          context.administrator,
          ~p"/o/#{context.organisation.short_name}/members"
        )

      assert html =~ "Invite a person"
      assert has_element?(view, "#invite_role_id option[selected]", "Member")

      address = unique_address()
      view |> form("#invite", invite: %{email: address}) |> render_submit()

      assert render_async(view) =~ address
      # A job sends the email of the invitation (ADR 0067).
      send_invitations()
      assert_email_sent(fn email -> email.to == [{"", address}] end)
      assert role_key_of(context, address) == :member
    end

    test "gives the role of a member for a role that the form did not offer", context do
      {view, _html} =
        open(
          context.conn,
          context.administrator,
          ~p"/o/#{context.organisation.short_name}/members"
        )

      address = unique_address()

      render_submit(view, "invite", %{
        "invite" => %{"email" => address, "role_id" => Ash.UUID.generate()}
      })

      assert role_key_of(context, address) == :member
    end

    test "lets an administrator give a member a role, and remove a member", context do
      {another, _user} = member!(context.organisation, :member, context.administrator)
      path = ~p"/o/#{context.organisation.short_name}/members"
      {view, html} = open(context.conn, context.administrator, path)

      assert html =~ "Give the role"
      administrator = role_with_key(context, :administrator)

      # The open pages of that person have the old role: they close.
      RescordWeb.Endpoint.subscribe(RescordWeb.UserAuth.socket_id(another.user_id))

      view
      |> form("#role-of-#{another.id}", member_role: %{role_id: administrator.id})
      |> render_submit()

      render_async(view)
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}

      assert %{role_id: id} =
               Accounts.member!(another.id, tenant: context.organisation, authorize?: false)

      assert id == administrator.id

      # The administrator cannot remove the one who is an administrator now.
      render_click(view, "remove", %{"id" => another.id})
      assert has_element?(view, "main p[role=alert]")

      assert Accounts.member!(another.id, tenant: context.organisation, authorize?: false)

      {:ok, _organisation, plain_member} =
        Accounts.organisation_for(context.member, context.organisation.short_name)

      render_click(view, "remove", %{"id" => plain_member.id})
      render_async(view)

      assert Accounts.member!(plain_member.id, tenant: context.organisation, authorize?: false) ==
               nil
    end

    test "does nothing for a member who sends an event that the page did not offer", context do
      path = ~p"/o/#{context.organisation.short_name}/members"
      {view, _html} = open(context.conn, context.member, path)

      {:ok, _organisation, own} =
        Accounts.organisation_for(context.member, context.organisation.short_name)

      administrator = role_with_key(context, :administrator)

      render_submit(view, "set_role", %{
        "member_id" => own.id,
        "member_role" => %{"role_id" => administrator.id}
      })

      render_submit(view, "invite", %{"invite" => %{"email" => unique_address()}})
      assert has_element?(view, "main p[role=alert]")

      assert %{role_id: role_id} =
               Accounts.member!(own.id, tenant: context.organisation, authorize?: false)

      assert role_id == role_with_key(context, :member).id
      # The refused invitation wrote no job, so no email goes out.
      assert %{success: 0, failure: 0} = send_invitations()
      assert_no_email_sent()
    end

    test "lets a root user invite an administrator", context do
      {view, _html} =
        open(context.conn, context.root, ~p"/o/#{context.organisation.short_name}/members")

      address = unique_address()

      view
      |> form("#invite",
        invite: %{email: address, role_id: role_with_key(context, :administrator).id}
      )
      |> render_submit()

      assert role_key_of(context, address) == :administrator
    end
  end

  test "a person who is invited signs in with a link, and finds the organisation", context do
    address = unique_address()

    Accounts.invite_member!(address, actor: context.administrator, tenant: context.organisation)
    flush_emails()

    # The limit of a client counts an address of the network.
    conn = %{context.conn | remote_ip: {10, 9, 9, rem(System.unique_integer([:positive]), 250)}}

    post(conn, ~p"/sign-in", %{"email" => address})
    wait_for_sign_in_tasks()
    assert_received {:email, email}

    signed_in = post(conn, ~p"/sign-in/link", %{"token" => token_in(email)})
    html = signed_in |> recycle() |> get(~p"/") |> html_response(200)

    assert html =~ "Wattle Creek"
    assert html =~ address
  end
end
