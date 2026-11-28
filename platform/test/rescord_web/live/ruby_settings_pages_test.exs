defmodule RescordWeb.RubySettingsPagesTest do
  @moduledoc """
  Holds the page of the settings of the assistant in an organisation, and
  its part of the settings page (ADR 0069): who sets Ruby, each control of
  the form, each place where Ruby stands, and the agreement to the place
  of the records.

  Each test creates an organisation, so the tests do not run beside others.
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import RescordWeb.Roles
  import Rescord.AccountsFixtures
  import Rescord.RubyFixtures

  alias Rescord.Ruby
  alias RescordWeb.{RoleWords, RubyWords}

  setup context do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, user} = member!(organisation, :member, administrator)

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     user: user,
     admin: [actor: administrator, tenant: organisation],
     path: ~p"/o/#{organisation.short_name}/settings/ruby",
     settings_path: ~p"/o/#{organisation.short_name}/settings",
     conn: sign_in(context.conn, administrator)}
  end

  defp offered!(root, values \\ %{}) do
    root |> provider!(values) |> Ruby.change_provider!(%{offered: true}, actor: root)
  end

  defp gateway!(root, name \\ "The gateway", address \\ "https://llm.example.org/v1") do
    offered!(root, %{name: name, kind: :openai_compatible, model: "a-model", base_url: address})
  end

  defp open(conn, path) do
    {:ok, view, _html} = live(conn, path)
    {view, render_async(view)}
  end

  defp save(view, conn, fields) do
    {:ok, view, _html} =
      view |> form("#ruby-settings", ruby: fields) |> render_submit() |> follow_redirect(conn)

    {view, render_async(view)}
  end

  defp turn_on!(context, provider) do
    [offer] = Enum.filter(Ruby.offers(context.admin), &(&1.id == provider.id))

    {:ok, settings} =
      Ruby.save_settings(
        %{enabled: true, provider_id: provider.id, agreed_to: offer.place_key},
        context.admin
      )

    settings
  end

  describe "who opens the page" do
    test "no user of another organisation, and nobody with no sign-in", context do
      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)

      assert {:error, {:redirect, %{to: "/"}}} =
               build_conn() |> sign_in(outsider) |> live(context.path)

      assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), context.path)
    end

    test "a member with no power settings reads that they cannot, and nothing else", context do
      provider = offered!(context.root, %{name: "A name that no member reads"})
      turn_on!(context, provider)

      {view, html} = context.conn |> recycle() |> sign_in(context.user) |> open(context.path)

      assert has_element?(view, "#ruby-refused", RoleWords.power(:settings))
      assert html =~ "It is on."
      refute html =~ provider.name
      refute html =~ "Anthropic"
      refute has_element?(view, "form")
      refute has_element?(view, "#ruby-place")

      # An event that the page does not offer changes nothing.
      render_submit(view, "save", %{"ruby" => %{"enabled" => "false", "retention_days" => "1"}})
      render_submit(view, "agree", %{})

      assert %{enabled: true, retention_days: 90} = Ruby.settings(context.organisation)
    end

    test "a root user who is no member sets Ruby", context do
      offered!(context.root)
      {view, _html} = context.conn |> recycle() |> sign_in(context.root) |> open(context.path)

      {view, html} = save(view, sign_in(build_conn(), context.root), %{enabled: "true"})

      assert html =~ "The settings of Ruby are saved. Ruby is on."
      assert has_element?(view, "#ruby-enabled[checked]")
    end
  end

  describe "a server that offers no provider" do
    test "has nothing to turn on, and no form", context do
      # A provider that the root user does not offer is none.
      provider!(context.root)

      {view, html} = open(context.conn, context.path)

      assert has_element?(view, "#ruby-not-set-up", "Ruby is not set up on this server")
      assert html =~ "It is not set up on this server."
      refute has_element?(view, "form")
      refute has_element?(view, "#ruby-enabled")

      {view, _html} = open(context.conn, context.settings_path)
      ruby = region("Ruby, the assistant")
      assert text(view, ruby) =~ "Ruby is not set up on this server"
      refute has?(view, ruby |> link("The settings of Ruby"))
    end
  end

  describe "a server that offers one provider" do
    setup context do
      {:ok, provider: offered!(context.root)}
    end

    test "shows the place, and Ruby is off at first", context do
      {view, html} = open(context.conn, context.path)

      assert has_element?(
               view,
               "#ruby-place",
               "Records go to Anthropic, in the United States and other countries."
             )

      assert html =~ "It is off until a person who can change the settings turns it on."
      refute has_element?(view, "#ruby-enabled[checked]")
      refute has_element?(view, "#ruby-agreed")
      refute has_element?(view, "#ruby-services")
      # The allowance starts at the amount of the provider, and the days at 90.
      assert has_element?(view, ~s(#ruby_allowance[value="20"]))
      assert has_element?(view, ~s(#ruby_retention_days[value="90"]))
      # The page says that no member can ask yet.
      assert has_element?(view, "#ruby-no-page", "no page where a member asks Ruby yet")
      assert has_element?(view, ~s(a[href="/o/#{context.organisation.short_name}/roles"]))
      # Nothing of the provider but its place: no name of a model, no key.
      refute html =~ context.provider.model
      refute html =~ key()
    end

    test "the box turns Ruby on, and writes the agreement", context do
      {view, _html} = open(context.conn, context.path)
      {view, html} = save(view, context.conn, %{enabled: "true"})

      assert html =~ "The settings of Ruby are saved. Ruby is on."
      assert html =~ "It is on."
      assert has_element?(view, "#ruby-enabled[checked]")
      assert has_element?(view, "#ruby-agreed", "Wattle Creek agreed to this place on")

      settings = Ruby.settings(context.organisation)
      assert settings.enabled
      assert settings.provider_id == context.provider.id
      assert settings.agreed_destination == "anthropic"
      assert settings.allowance == 2_000
      assert Ruby.status(context.organisation) == :on

      # The box turns it off again.
      {view, html} = save(view, context.conn, %{enabled: "false"})
      assert html =~ "The settings of Ruby are saved. Ruby is off."
      refute has_element?(view, "#ruby-enabled[checked]")
      refute has_element?(view, "#ruby-agreed")
      assert Ruby.status(context.organisation) == :off
    end

    test "the allowance and the days are saved, also with Ruby off", context do
      {view, _html} = open(context.conn, context.path)
      {view, _html} = save(view, context.conn, %{allowance: "12.50", retention_days: "30"})

      assert has_element?(view, ~s(#ruby_allowance[value="12.50"]))
      assert has_element?(view, ~s(#ruby_retention_days[value="30"]))

      assert %{enabled: false, allowance: 1_250, retention_days: 30} =
               Ruby.settings(context.organisation)

      # An empty allowance takes the amount of the provider again.
      {view, _html} = save(view, context.conn, %{allowance: ""})
      assert has_element?(view, ~s(#ruby_allowance[value="20"]))
    end

    test "a value that is none is refused beside its field, and the form keeps it", context do
      {view, _html} = open(context.conn, context.path)

      html =
        view
        |> form("#ruby-settings", ruby: %{enabled: "true", allowance: "a lot"})
        |> render_submit()

      assert html =~ "give an amount in US dollars, such as 20 or 0.50"
      assert has_element?(view, ~s(#ruby_allowance[aria-invalid="true"][value="a lot"]))
      assert has_element?(view, "#ruby-enabled[checked]")

      for {days, field} <- [{"0", "retention_days"}, {"4000", "retention_days"}] do
        view
        |> form("#ruby-settings", ruby: %{allowance: "20", retention_days: days})
        |> render_submit()

        assert has_element?(view, ~s(#ruby_#{field}[aria-invalid="true"][value="#{days}"]))
      end

      assert Ruby.status(context.organisation) == :off
      assert Ash.read!(Ruby.Settings, tenant: context.organisation, authorize?: false) == []
    end

    test "a forged provider is none: the page takes the provider from what it showed", context do
      hidden = provider!(context.root, %{name: "Not offered"})
      {view, _html} = open(context.conn, context.path)

      html =
        render_submit(view, "save", %{
          "ruby" => %{"enabled" => "true", "provider_id" => hidden.id, "retention_days" => "90"}
        })

      assert html =~ "Ruby is not on: choose the service first."
      assert Ruby.status(context.organisation) == :off
    end

    test "the settings page says where Ruby stands, with a link for who can set it", context do
      {view, _html} = open(context.conn, context.settings_path)
      assert has_element?(view, "section[aria-labelledby=ruby-heading] dd", "Off")
      assert has_element?(view, ~s(#ruby-settings-link[href="#{context.path}"]))

      turn_on!(context, context.provider)
      {view, _html} = open(context.conn, context.settings_path)
      assert has_element?(view, "section[aria-labelledby=ruby-heading] dd", "On")

      {view, _html} =
        context.conn |> recycle() |> sign_in(context.user) |> open(context.settings_path)

      assert has_element?(view, "section[aria-labelledby=ruby-heading] dd", "On")
      refute has_element?(view, "#ruby-settings-link")
    end
  end

  describe "a server that offers more than one provider" do
    setup context do
      {:ok, anthropic: offered!(context.root), gateway: gateway!(context.root)}
    end

    test "gives a choice, each with its place, and none is chosen at first", context do
      {view, _html} = open(context.conn, context.path)

      assert has_element?(view, "#ruby-services legend", "The service of Ruby")
      refute has_element?(view, "#ruby-place")

      for provider <- [context.anthropic, context.gateway] do
        assert has_element?(
                 view,
                 ~s(input[type=radio][form="ruby-settings"][value="#{provider.id}"])
               )

        refute has_element?(view, ~s(input[type=radio][value="#{provider.id}"][checked]))
        assert has_element?(view, "#ruby-place-#{provider.id}", Ruby.place(provider))
      end

      # With no service, Ruby does not go on.
      html = render_submit(view, "save", %{"ruby" => %{"enabled" => "true"}})
      assert html =~ "Ruby is not on: choose the service first."
      assert Ruby.status(context.organisation) == :off
    end

    test "the chosen service is the one that the organisation agrees to", context do
      {view, _html} = open(context.conn, context.path)

      {:ok, view, _html} =
        view
        |> render_submit("save", %{
          "ruby" => %{
            "enabled" => "true",
            "provider_id" => context.gateway.id,
            "allowance" => "",
            "retention_days" => "90"
          }
        })
        |> follow_redirect(context.conn)

      assert has_element?(view, ~s(input[type=radio][value="#{context.gateway.id}"][checked]))
      refute has_element?(view, ~s(input[type=radio][value="#{context.anthropic.id}"][checked]))

      settings = Ruby.settings(context.organisation)
      assert settings.provider_id == context.gateway.id
      assert settings.agreed_destination == "address:https://llm.example.org/v1"
      assert Ruby.status(context.organisation) == :on
    end
  end

  describe "the place of the provider changed" do
    setup context do
      provider = gateway!(context.root)
      first = turn_on!(context, provider)

      {:ok, moved} =
        Ruby.change_provider(provider, %{base_url: "https://elsewhere.example.org/v1"},
          actor: context.root
        )

      {:ok, provider: moved, first: first}
    end

    test "the page says so, shows the new place, and the button agrees", context do
      {view, html} = open(context.conn, context.path)

      assert has_element?(view, "#ruby-stopped[role=alert]", "changed where the records go")
      assert html =~ "It is off until a person who can change the settings agrees"
      assert has_element?(view, "#ruby-place", "elsewhere.example.org")
      refute has_element?(view, "#ruby-agreed")
      # The box says what a member gets: nothing.
      refute has_element?(view, "#ruby-enabled[checked]")

      {:ok, view, html} =
        view |> form("#ruby-agree") |> render_submit() |> follow_redirect(context.conn)

      assert html =~ "The settings of Ruby are saved. Ruby is on."
      refute has_element?(view, "#ruby-stopped")
      refute has_element?(view, "#ruby-agree")
      assert has_element?(view, "#ruby-agreed")

      settings = Ruby.settings(context.organisation)
      assert settings.agreed_destination == "address:https://elsewhere.example.org/v1"
      assert DateTime.compare(settings.agreed_at, context.first.agreed_at) == :gt
      assert Ruby.status(context.organisation) == :on
    end

    test "with a choice of services, the person agrees in the form", context do
      offered!(context.root)
      {view, _html} = open(context.conn, context.path)

      assert has_element?(view, "#ruby-stopped[role=alert]")
      # The button would agree to a service that the person did not choose.
      refute has_element?(view, "#ruby-agree")
      assert has_element?(view, ~s(input[type=radio][value="#{context.provider.id}"][checked]))
      refute has_element?(view, "#ruby-enabled[checked]")

      {view, _html} = save(view, context.conn, %{enabled: "true"})
      refute has_element?(view, "#ruby-stopped")

      assert Ruby.settings(context.organisation).agreed_destination ==
               "address:https://elsewhere.example.org/v1"
    end

    test "a person who saves another field agrees to nothing", context do
      {view, _html} = open(context.conn, context.path)
      {view, _html} = save(view, context.conn, %{allowance: "5"})

      refute has_element?(view, "#ruby-enabled[checked]")
      settings = Ruby.settings(context.organisation)
      refute settings.enabled
      assert settings.allowance == 500
      assert settings.agreed_destination == context.first.agreed_destination
    end

    test "the settings page says that Ruby is off", context do
      {view, _html} = open(context.conn, context.settings_path)

      assert has_element?(
               view,
               "section[aria-labelledby=ruby-heading] dd",
               RubyWords.state({:stopped, :place})
             )
    end
  end

  describe "the place changes while the page is open" do
    test "nobody agrees to a place that the page did not show", context do
      provider = gateway!(context.root)
      {view, _html} = open(context.conn, context.path)
      assert has_element?(view, "#ruby-place", "llm.example.org")

      {:ok, _moved} =
        Ruby.change_provider(provider, %{base_url: "https://elsewhere.example.org/v1"},
          actor: context.root
        )

      html = view |> form("#ruby-settings", ruby: %{enabled: "true"}) |> render_submit()

      assert html =~ "Ruby is not on: the place of the records is another one now"
      # The page shows the place as it is now, and Ruby is still off.
      assert has_element?(view, "#ruby-place", "elsewhere.example.org")
      assert Ruby.status(context.organisation) == :off

      # The person read it, and saves again.
      {_view, html} = save(view, context.conn, %{enabled: "true"})
      assert html =~ "Ruby is on."

      assert Ruby.settings(context.organisation).agreed_destination ==
               "address:https://elsewhere.example.org/v1"
    end
  end

  describe "the server takes the provider away" do
    test "with no other one, the page has no form", context do
      provider = offered!(context.root)
      turn_on!(context, provider)
      {:ok, _provider} = Ruby.change_provider(provider, %{offered: false}, actor: context.root)

      {view, _html} = open(context.conn, context.path)

      assert has_element?(view, "#ruby-stopped[role=alert]", "it offers no other one")
      refute has_element?(view, "form")
    end

    test "with another one, the person reads its place and turns Ruby on", context do
      provider = offered!(context.root)
      turn_on!(context, provider)
      :ok = Ruby.remove_provider(provider, actor: context.root)
      other = gateway!(context.root)

      {view, _html} = open(context.conn, context.path)

      assert has_element?(view, "#ruby-stopped[role=alert]", "does not offer the service")
      assert has_element?(view, "#ruby-place", "llm.example.org")
      refute has_element?(view, "#ruby-agree")
      refute has_element?(view, "#ruby-enabled[checked]")

      {view, _html} = save(view, context.conn, %{enabled: "true"})
      refute has_element?(view, "#ruby-stopped")

      settings = Ruby.settings(context.organisation)
      assert settings.provider_id == other.id
      assert Ruby.status(context.organisation) == :on
    end
  end

  describe "the page of a provider, for a root user" do
    test "says how many organisations have Ruby on with it", context do
      provider = offered!(context.root)
      conn = context.conn |> recycle() |> sign_in(context.root)

      {view, _html} = open(conn, ~p"/root/ruby/#{provider.id}")
      assert has_element?(view, "#provider-organisations", RubyWords.organisations(0))

      turn_on!(context, provider)
      {view, _html} = open(conn, ~p"/root/ruby/#{provider.id}")
      assert has_element?(view, "#provider-organisations", "1 organisation has Ruby on")
      assert has_element?(view, "#provider-organisations", "turns Ruby off")

      # A new provider has no organisation, and the page says none.
      {view, _html} = open(conn, ~p"/root/ruby/new")
      refute has_element?(view, "#provider-organisations")
    end
  end
end
