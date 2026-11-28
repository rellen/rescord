defmodule Rescord.Accounts.OrganisationTest do
  @moduledoc """
  Holds the rules of the organisations, their members and the grants
  (`docs/domain.md`, section 5.1):

    * a root user creates an organisation, which makes its schema;
    * a root user invites an administrator, and an administrator invites a
      member and can make a member an administrator;
    * a person sees only the organisations where they are a member;
    * a root user can do anything.

  A new organisation makes a schema, with a table that names the users. That
  takes a lock on the users, and two tests that do so at one time stop each
  other. So a test that creates an organisation does not run beside others.
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Swoosh.TestAssertions

  alias Rescord.Accounts
  alias Rescord.Accounts.{Grants, Member, Organisation}

  defmodule Down do
    @moduledoc "A mail server that does not answer."
    use Swoosh.Adapter

    @impl true
    def deliver(_email, _config), do: {:error, :econnrefused}
  end

  # The key of the role of a member: `:administrator` or `:member` (ADR 0040).
  defp role_key(member, organisation),
    do: Ash.load!(member, :role, tenant: organisation, authorize?: false).role.key

  setup do
    {:ok, root: root!()}
  end

  describe "an organisation" do
    test "comes from a root user, with a schema of its own", %{root: root} do
      organisation = organisation!(root)

      assert %{rows: [[1]]} =
               Repo.query!(
                 "select count(*)::int from information_schema.tables where table_schema = $1 and table_name = 'members'",
                 [Organisation.schema(organisation)]
               )

      assert Organisation.schema(organisation) in Repo.all_tenants()
    end

    test "does not come from a user who is not a root user, or from nobody" do
      for actor <- [user!(), nil] do
        assert {:error, %Ash.Error.Forbidden{}} =
                 Accounts.create_organisation(
                   %{name: "A", short_name: "a-refuge", time_zone: "Etc/UTC"},
                   actor: actor
                 )
      end
    end

    test "has a short name of small letters, digits and hyphens, that no other one has", %{
      root: root
    } do
      for short_name <- ["Wattle", "wattle creek", "-wattle", "wattle-", "wattle--creek", ""] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Accounts.create_organisation(
                   %{name: "A", short_name: short_name, time_zone: "Etc/UTC"},
                   actor: root
                 )
      end

      first = organisation!(root)

      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.create_organisation(
                 %{name: "B", short_name: first.short_name, time_zone: "Etc/UTC"},
                 actor: root
               )
    end
  end

  describe "an invitation" do
    setup %{root: root} do
      {:ok, organisation: organisation!(root, "Wattle Creek")}
    end

    test "from a root user makes an administrator, a user for the address, and an email", %{
      root: root,
      organisation: organisation
    } do
      address = unique_address()

      {member, user} = member!(organisation, :administrator, root, address)

      assert role_key(member, organisation) == :administrator
      assert member.user_id == user.id
      refute user.root?

      # The email is the work of a job, which the invitation wrote (ADR 0067).
      assert_no_email_sent()
      assert %{success: 1, failure: 0} = send_invitations()

      assert_email_sent(fn email ->
        assert email.to == [{"", address}]
        assert email.subject =~ "Wattle Creek"
        assert email.text_body =~ to_string(root.email)
        assert email.text_body =~ RescordWeb.SignInLink.page()
        # An invitation has no token: the person asks for a link.
        refute email.text_body =~ "token"
        true
      end)
    end

    @tag :capture_log
    test "sends its email again after a fault of the mail server", %{
      root: root,
      organisation: organisation
    } do
      mailer = Application.fetch_env!(:rescord, Rescord.Mailer)

      Shoddy.Tests.put_app_env(:rescord, Rescord.Mailer,
        adapter: Rescord.Accounts.OrganisationTest.Down
      )

      address = unique_address()
      {member, _user} = member!(organisation, :member, root, address)

      # The mail server is down. The member is there, and the job waits.
      assert %{success: 0, failure: 1} = send_invitations()
      assert_no_email_sent()
      assert Accounts.member!(member.id, tenant: organisation, authorize?: false)

      Application.put_env(:rescord, Rescord.Mailer, mailer)

      assert %{success: 1, failure: 0} = send_invitations(with_scheduled: true)
      assert_email_sent(fn email -> email.to == [{"", address}] end)
    end

    test "writes no job when the invitation is refused", %{root: root, organisation: organisation} do
      {_member, member} = member!(organisation, :member, root)
      assert %{success: 1} = send_invitations()
      assert_email_sent()

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.invite_member(unique_address(), actor: member, tenant: organisation)

      assert %{success: 0, failure: 0} = send_invitations()
      assert_no_email_sent()
    end

    test "has an email that no person sends by hand", %{root: root, organisation: organisation} do
      {_member, administrator} = member!(organisation, :administrator, root)

      signal =
        struct!(Rescord.Accounts.Signals.MemberInvited,
          signal_id: Ash.UUID.generate(),
          email: unique_address()
        )

      for actor <- [administrator, nil] do
        assert {:error, %Ash.Error.Forbidden{}} =
                 Member
                 |> Ash.ActionInput.for_action(:send_invitation, %{signal: signal},
                   actor: actor,
                   tenant: organisation
                 )
                 |> Ash.run_action()
      end
    end

    test "uses the user that an address has already", %{root: root, organisation: organisation} do
      user = user!()

      {member, found} =
        member!(organisation, :member, root, String.upcase(to_string(user.email)))

      assert found.id == user.id
      assert member.user_id == user.id
    end

    test "from an administrator makes a member, and not an administrator", %{
      root: root,
      organisation: organisation
    } do
      {_member, administrator} = member!(organisation, :administrator, root)

      {member, _user} = member!(organisation, :member, administrator)
      assert role_key(member, organisation) == :member

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.invite_administrator(unique_address(),
                 actor: administrator,
                 tenant: organisation
               )
    end

    test "does not come from a member, from a user outside the organisation, or from nobody",
         %{root: root, organisation: organisation} do
      {_member, member} = member!(organisation, :member, root)

      for actor <- [member, user!(), nil] do
        assert {:error, %Ash.Error.Forbidden{}} =
                 Accounts.invite_member(unique_address(), actor: actor, tenant: organisation)
      end
    end

    test "does not make a second member for a user", %{root: root, organisation: organisation} do
      address = unique_address()
      member!(organisation, :member, root, address)

      assert {:error, %Ash.Error.Invalid{} = error} =
               Accounts.invite_member(address, actor: root, tenant: organisation)

      assert Exception.message(error) =~ "is a member of the organisation already"
    end

    test "does not take a role or a user as input", %{root: root, organisation: organisation} do
      for extra <- [%{role: :administrator}, %{user_id: root.id}] do
        assert_raise Ash.Error.Invalid, fn ->
          Member
          |> Ash.Changeset.for_create(
            :invite_member,
            Map.merge(%{email: unique_address()}, extra),
            actor: root,
            tenant: organisation
          )
          |> Ash.create!()
        end
      end
    end
  end

  describe "the members of an organisation" do
    setup %{root: root} do
      organisation = organisation!(root)
      {_, administrator} = member!(organisation, :administrator, root)
      {member, user} = member!(organisation, :member, administrator)

      {:ok, organisation: organisation, administrator: administrator, member: member, user: user}
    end

    test "are there for each member, with their addresses", context do
      for actor <- [context.administrator, context.user, context.root] do
        members = Accounts.members!(actor: actor, tenant: context.organisation, load: [:email])

        assert length(members) == 2
        assert to_string(context.user.email) in Enum.map(members, &to_string(&1.email))
      end
    end

    test "are not there for a user of another organisation, or for nobody", context do
      other = organisation!(context.root)
      {_, outsider} = member!(other, :administrator, context.root)

      for actor <- [outsider, user!(), nil] do
        assert Accounts.members!(actor: actor, tenant: context.organisation) == []
      end

      # Positive control: the outsider does read their own organisation.
      assert [_one] = Accounts.members!(actor: outsider, tenant: other)
    end

    test "an administrator makes a member an administrator, and a member cannot", context do
      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.make_administrator(context.member,
                 actor: context.user,
                 tenant: context.organisation
               )

      assert {:ok, promoted} =
               Accounts.make_administrator(context.member,
                 actor: context.administrator,
                 tenant: context.organisation
               )

      assert role_key(promoted, context.organisation) == :administrator
    end

    test "only a root user makes an administrator a member again", context do
      {:ok, promoted} =
        Accounts.make_administrator(context.member,
          actor: context.administrator,
          tenant: context.organisation
        )

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.make_member(promoted,
                 actor: context.administrator,
                 tenant: context.organisation
               )

      assert {:ok, demoted} =
               Accounts.make_member(promoted, actor: context.root, tenant: context.organisation)

      assert role_key(demoted, context.organisation) == :member
    end

    test "an administrator removes a member, and not another administrator", context do
      {other_administrator, _user} = member!(context.organisation, :administrator, context.root)

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.remove_member(other_administrator,
                 actor: context.administrator,
                 tenant: context.organisation
               )

      assert :ok =
               Accounts.remove_member(context.member,
                 actor: context.administrator,
                 tenant: context.organisation
               )

      assert Accounts.organisation_for(context.user, context.organisation.short_name) == :error

      # The row stays, archived, and the person can be invited again.
      assert %{rows: [[1]]} =
               Repo.query!(
                 "select count(*)::int from \"#{Organisation.schema(context.organisation)}\".members where archived_at is not null"
               )

      assert {_member, again} =
               member!(
                 context.organisation,
                 :member,
                 context.administrator,
                 to_string(context.user.email)
               )

      assert again.id == context.user.id
    end

    test "a member removes nobody", context do
      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.remove_member(context.member,
                 actor: context.user,
                 tenant: context.organisation
               )
    end

    test "a version of a member names who made the change", context do
      {:ok, _} =
        Accounts.make_administrator(context.member,
          actor: context.administrator,
          tenant: context.organisation
        )

      versions =
        Member.Version
        |> Ash.read!(tenant: context.organisation, authorize?: false)
        |> Enum.filter(&(&1.version_source_id == context.member.id))

      assert [:invite_member, :make_administrator] ==
               versions |> Enum.map(& &1.version_action_name) |> Enum.sort()

      assert Enum.all?(versions, &(&1.user_id == context.administrator.id))
    end
  end

  describe "the time zone of an organisation" do
    setup %{root: root} do
      organisation = organisation!(root, "Wattle Creek", "Australia/Brisbane")
      {_, administrator} = member!(organisation, :administrator, root)
      {_, member} = member!(organisation, :member, administrator)
      {:ok, organisation: organisation, administrator: administrator, member: member}
    end

    test "is necessary, and is a name that the time zone rules know", %{root: root} do
      for zone <- [nil, "", "Brisbane", "Australia/Atlantis", "+10:00"] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Accounts.create_organisation(
                   %{name: "A", short_name: "a-refuge", time_zone: zone},
                   actor: root
                 )
      end

      assert Accounts.time_zone?("Australia/Brisbane")
      assert Accounts.time_zone?("Etc/UTC")
      refute Accounts.time_zone?("Australia/Atlantis")
      refute Accounts.time_zone?(nil)
    end

    test "says what the date is in the organisation at an instant", context do
      # 20:00 in UTC is 06:00 on the next day in Brisbane, which is 10 hours ahead.
      evening = ~U[2026-11-15 20:00:00Z]
      assert Accounts.local_date(context.organisation, evening) == ~D[2026-11-16]
      assert Accounts.local_date(context.organisation, ~U[2026-11-15 13:59:59Z]) == ~D[2026-11-15]

      # An action has the name of the schema in place of the organisation.
      schema = Rescord.Accounts.Organisation.schema(context.organisation)
      assert Accounts.local_date(schema, evening) == ~D[2026-11-16]
      assert Accounts.time_zone_of(schema) == "Australia/Brisbane"

      assert Accounts.today(context.organisation) in [
               Date.utc_today(),
               Date.add(Date.utc_today(), 1)
             ]
    end

    test "changes for an administrator and for a root user, and the version names who", context do
      assert {:ok, %{time_zone: "Australia/Perth"}} =
               Accounts.set_organisation_time_zone(context.organisation, "Australia/Perth",
                 actor: context.administrator
               )

      assert {:ok, %{time_zone: "Australia/Hobart"}} =
               Accounts.set_organisation_time_zone(context.organisation, "Australia/Hobart",
                 actor: context.root
               )

      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.set_organisation_time_zone(context.organisation, "Hobart",
                 actor: context.administrator
               )

      version = AshPaperTrail.Resource.Info.version_resource(Rescord.Accounts.Organisation)

      users =
        version
        |> Ash.read!(authorize?: false)
        |> Enum.filter(&(&1.version_source_id == context.organisation.id))
        |> Enum.filter(&(&1.version_action_name == :set_time_zone))
        |> Enum.map(& &1.user_id)

      assert Enum.sort(users) == Enum.sort([context.administrator.id, context.root.id])
    end

    test "does not change for a member, for a user of another organisation, or for nobody",
         context do
      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)

      for actor <- [context.member, outsider, user!(), nil] do
        assert {:error, %Ash.Error.Forbidden{}} =
                 Accounts.set_organisation_time_zone(context.organisation, "Australia/Perth",
                   actor: actor
                 )
      end

      assert Accounts.time_zone_of(Rescord.Accounts.Organisation.schema(context.organisation)) ==
               "Australia/Brisbane"

      assert Accounts.role_can_change_settings?(:administrator)
      assert Accounts.role_can_change_settings?(:root)
      refute Accounts.role_can_change_settings?(:member)
      refute Accounts.role_can_change_settings?(nil)
    end

    test "has suggestions for a form, each a name that the rules know" do
      zones = Accounts.time_zones()

      assert "Australia/Brisbane" in zones
      assert length(zones) > 300
      assert Enum.all?(zones, &Accounts.time_zone?/1)
    end
  end

  describe "the locale of an organisation" do
    setup %{root: root} do
      organisation = organisation!(root, "Wattle Creek", "Australia/Brisbane")
      {_, administrator} = member!(organisation, :administrator, root)
      {_, member} = member!(organisation, :member, administrator)
      {:ok, organisation: organisation, administrator: administrator, member: member}
    end

    test "is the default at first, and a root user can give another one", context do
      assert context.organisation.locale == "en-AU"
      assert Accounts.default_locale() == "en-AU"

      assert {:ok, %{locale: "en-US"}} =
               Accounts.create_organisation(
                 %{name: "A", short_name: "a-refuge", time_zone: "Etc/UTC", locale: "en-US"},
                 actor: context.root
               )
    end

    test "is one that Rescord offers", %{root: root} do
      for locale <- ["", "fr", "en-au", "en", "English (Australia)"] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Accounts.create_organisation(
                   %{name: "A", short_name: "a-refuge", time_zone: "Etc/UTC", locale: locale},
                   actor: root
                 )
      end

      assert Accounts.locale?("en-AU")
      assert Accounts.locale?("en-001")
      refute Accounts.locale?("fr")
      refute Accounts.locale?("en-au")
      refute Accounts.locale?(nil)
      refute Accounts.locale?(:"en-AU")
    end

    test "has a list with a name for each locale, in the order of the names" do
      locales = Accounts.locales()

      assert {"en-AU", "English (Australia)"} in locales
      assert Accounts.default_locale() in Enum.map(locales, &elem(&1, 0))
      assert Enum.all?(locales, fn {tag, name} -> Accounts.locale?(tag) and name =~ "English" end)
      assert Accounts.locale_name("en-GB") == "English (United Kingdom)"
      assert Accounts.locale_name("fr") == "fr"

      names = for {tag, name} <- locales, tag != "en-001", do: name
      assert names == Enum.sort(names)
      assert List.last(locales) == {"en-001", "English (world)"}
    end

    test "changes for an administrator and for a root user, and the version names who", context do
      assert {:ok, %{locale: "en-US"}} =
               Accounts.set_organisation_locale(context.organisation, "en-US",
                 actor: context.administrator
               )

      assert {:ok, %{locale: "en-GB"}} =
               Accounts.set_organisation_locale(context.organisation, "en-GB",
                 actor: context.root
               )

      for locale <- ["fr", "en-gb", "", nil] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Accounts.set_organisation_locale(context.organisation, locale,
                   actor: context.administrator
                 )
      end

      version = AshPaperTrail.Resource.Info.version_resource(Rescord.Accounts.Organisation)

      users =
        version
        |> Ash.read!(authorize?: false)
        |> Enum.filter(&(&1.version_source_id == context.organisation.id))
        |> Enum.filter(&(&1.version_action_name == :set_locale))
        |> Enum.map(& &1.user_id)

      assert Enum.sort(users) == Enum.sort([context.administrator.id, context.root.id])
    end

    test "does not change for a member, for a user of another organisation, or for nobody",
         context do
      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)

      for actor <- [context.member, outsider, user!(), nil] do
        assert {:error, %Ash.Error.Forbidden{}} =
                 Accounts.set_organisation_locale(context.organisation, "en-US", actor: actor)
      end

      assert {:ok, %{locale: "en-AU"}} =
               Accounts.organisation_by_short_name(context.organisation.short_name,
                 actor: context.root
               )
    end
  end

  describe "the paper of the reports of an organisation" do
    setup %{root: root} do
      organisation = organisation!(root, "Wattle Creek", "Australia/Brisbane")
      {_, administrator} = member!(organisation, :administrator, root)
      {_, member} = member!(organisation, :member, administrator)
      {:ok, organisation: organisation, administrator: administrator, member: member}
    end

    test "is A4 at first, and the list of the papers is the list of the attribute", context do
      assert context.organisation.paper_size == :a4

      attribute = Ash.Resource.Info.attribute(Rescord.Accounts.Organisation, :paper_size)
      assert attribute.default == :a4
      assert attribute.constraints[:one_of] == Accounts.paper_sizes()
      assert Accounts.paper_sizes() == [:a4, :us_letter]

      # A text names a paper only as the value of a form has it.
      assert Accounts.paper_size("a4") == :a4
      assert Accounts.paper_size("us_letter") == :us_letter

      for other <- ["", "A4", "us-letter", "a3", nil, 4] do
        assert Accounts.paper_size(other) == nil
      end
    end

    test "changes for an administrator and for a root user, and the version names who",
         context do
      assert {:ok, %{paper_size: :us_letter} = letter} =
               Accounts.set_organisation_paper_size(context.organisation, :us_letter,
                 actor: context.administrator
               )

      assert {:ok, %{paper_size: :a4}} =
               Accounts.set_organisation_paper_size(letter, :a4, actor: context.root)

      for paper <- [:a3, "a3", "", nil] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Accounts.set_organisation_paper_size(context.organisation, paper,
                   actor: context.administrator
                 )
      end

      version = AshPaperTrail.Resource.Info.version_resource(Rescord.Accounts.Organisation)

      users =
        version
        |> Ash.read!(authorize?: false)
        |> Enum.filter(&(&1.version_source_id == context.organisation.id))
        |> Enum.filter(&(&1.version_action_name == :set_paper_size))
        |> Enum.map(& &1.user_id)

      assert Enum.sort(users) == Enum.sort([context.administrator.id, context.root.id])
    end

    test "does not change for a member, for a user of another organisation, or for nobody",
         context do
      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)

      for actor <- [context.member, outsider, user!(), nil] do
        assert {:error, %Ash.Error.Forbidden{}} =
                 Accounts.set_organisation_paper_size(context.organisation, :us_letter,
                   actor: actor
                 )
      end

      assert {:ok, %{paper_size: :a4}} =
               Accounts.organisation_by_short_name(context.organisation.short_name,
                 actor: context.root
               )
    end
  end

  describe "the organisations of a user" do
    test "are the ones where the user is a member, and each one for a root user", %{root: root} do
      mine = organisation!(root, "Mine")
      other = organisation!(root, "Other")
      {_, user} = member!(mine, :member, root)

      assert [found] = Accounts.organisations_for(user)
      assert found.id == mine.id

      assert Enum.map(Accounts.organisations_for(root), & &1.id) |> Enum.sort() ==
               Enum.sort([mine.id, other.id])

      assert Accounts.organisations_for(user!()) == []
    end

    test "open by their short name for a member and for a root user, and for nobody else", %{
      root: root
    } do
      organisation = organisation!(root)
      {member, user} = member!(organisation, :member, root)

      assert {:ok, found, found_member} = Accounts.organisation_for(user, organisation.short_name)
      assert found.id == organisation.id
      assert found_member.id == member.id

      assert {:ok, _organisation, nil} = Accounts.organisation_for(root, organisation.short_name)

      # No such organisation, and one that the user cannot open, look the same.
      assert Accounts.organisation_for(user!(), organisation.short_name) == :error
      assert Accounts.organisation_for(user, "no-such-refuge") == :error
    end
  end

  describe "the grants" do
    test "name only resources and actions that exist" do
      for role <- Grants.roles(), {resource, action, scope} <- Grants.grants(role) do
        assert Ash.Resource.Info.action(resource, action),
               "#{inspect(resource)} has no action #{action}"

        # The scope has a filter.
        assert Grants.filter(resource, scope) != nil
      end
    end

    test "give a member less than an administrator" do
      # A member has no action that an administrator does not have. The scope
      # of a member can be less: the entries that they wrote, for example.
      actions = fn role ->
        for {resource, action, _scope} <- Grants.grants(role), do: {resource, action}
      end

      assert actions.(:member) -- actions.(:administrator) == []
      assert length(Grants.grants(:administrator)) > length(Grants.grants(:member))

      # What is of one person stays theirs, for an administrator too
      # (ADR 0106): the follows, the notifications and the preferences of a
      # person, and the change of a comment, which only its writer makes.
      of_one_person = [
        {Rescord.Comments.Follow, :read},
        {Rescord.Comments.Follow, :unfollow},
        {Rescord.Comments.Comment, :revise},
        {Rescord.Notifications.Notification, :read},
        {Rescord.Notifications.Notification, :mine},
        {Rescord.Notifications.Notification, :mark_read},
        {Rescord.Notifications.Preference, :read}
      ]

      for {resource, action, scope} <- Grants.grants(:member),
          scope != :all,
          {resource, action} not in of_one_person do
        assert {:ok, :all} = Grants.scope(:administrator, resource, action)
      end

      assert Grants.grants(:nobody) == []
    end

    test "give nobody the invitation of an administrator: that is for a root user" do
      for role <- Grants.roles() do
        assert Grants.scope(role, Member, :invite_administrator) == :none
        assert Grants.scope(role, Member, :make_member) == :none
      end
    end
  end
end
