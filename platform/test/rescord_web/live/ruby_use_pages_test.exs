defmodule RescordWeb.RubyUsePagesTest do
  @moduledoc """
  Holds the use of the month of Ruby on its settings page (ADR 0069): the
  share of the allowance that went, the words from 80% on, and the table
  of the replies and the cost of each member, with no word of any
  conversation. Only a person whose role has the power `settings` reads it.
  The tests find what a person finds (ADR 0107).

  The rows of the use are written as the job of a reply writes them: no
  reply runs here, and no test calls a provider.

  Each test creates an organisation, so the tests do not run beside others.
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Rescord.AccountsFixtures
  import Rescord.ClockFixtures
  import Rescord.RubyFixtures

  alias Rescord.{Accounts, Ruby}
  alias Rescord.Ruby.Allowance
  alias RescordWeb.RubyWords

  setup context do
    # The use is of a month of UTC: the rows of a test are of its day.
    clear_of_edge(:timer.hours(24))

    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    admin = [actor: administrator, tenant: organisation]
    {ana_member, ana} = member!(organisation, :member, administrator)
    ruby_on!(root, admin)

    # An allowance of 20 US dollars.
    [offer] = Ruby.offers(admin)

    {:ok, _settings} =
      Ruby.save_settings(
        %{enabled: true, provider_id: offer.id, agreed_to: offer.place_key, allowance: 2_000},
        admin
      )

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     admin: admin,
     ana: ana,
     ana_member: ana_member,
     path: ~p"/o/#{organisation.short_name}/settings/ruby",
     conn: sign_in(context.conn, administrator)}
  end

  # The counts of replies of one member and one model on a day.
  defp used!(context, user_id, replies, microdollars, day \\ Date.utc_today()) do
    Allowance.add!(
      user_id,
      "claude-opus-5-5",
      %{replies: replies, requests: replies, cost_microdollars: microdollars},
      context.organisation,
      day
    )
  end

  # The address of a user, as a part of a pattern.
  defp email(user), do: user.email |> to_string() |> Regex.escape()

  defp use_section, do: main() |> region("The use of #{month()}")
  defp members, do: use_section() |> table("The replies and the cost of each member")

  defp month,
    do: Date.utc_today() |> Date.beginning_of_month() |> RescordWeb.Locale.month()

  describe "the use of the month" do
    test "the share of the allowance, and the replies and the cost of each member", context do
      used!(context, context.administrator.id, 3, 12_400_000)
      used!(context, context.ana.id, 2, 3_000_000)

      # A row of last month is in no sum of this one.
      last_month = Date.utc_today() |> Date.beginning_of_month() |> Date.add(-1)
      used!(context, context.ana.id, 40, 90_000_000, last_month)

      session =
        context.conn
        |> visit(context.path)
        |> assert_has(use_section(), text: "About 15.40 of 20 US dollars used")
        |> refute_has(use_section(), text: "80%")
        |> assert_has(
          members()
          |> row(~r/^#{email(context.administrator)}\s+3\s+about 12\.40$/)
        )
        |> assert_has(members() |> row(~r/^#{email(context.ana)}\s.*about 3\.00$/s))

      # The meter of the label holds the cents, and turns at 80% of the
      # allowance.
      assert_has(
        session,
        "label[for=ruby-used] + meter#ruby-used[max=\"2000\"][high=\"1600\"][value=\"1540\"]"
      )

      # The largest cost first.
      assert [first, second] = names(session, members() |> row(~r/about/))
      assert first =~ to_string(context.administrator.email)
      assert second =~ to_string(context.ana.email)

      # No word of a conversation, and no model.
      refute_has(session, use_section(), text: "claude")
    end

    test "says so from 80% of the allowance on, and when it is all used", context do
      used!(context, context.ana.id, 5, 16_000_000)

      context.conn
      |> visit(context.path)
      |> assert_has(use_section(),
        text: "80% or more of the allowance of #{month()} is used."
      )

      used!(context, context.ana.id, 2, 4_100_000)

      context.conn
      |> visit(context.path)
      |> assert_has(use_section(), text: "About 20.10 of 20 US dollars used")
      |> assert_has(use_section(),
        text: "The allowance of #{month()} is used: Ruby answers nobody until the next month"
      )
    end

    test "says that the allowance is used exactly when Ruby refuses a message", context do
      month = Date.beginning_of_month(Date.utc_today())
      used!(context, context.ana.id, 1, 19_994_999)

      for more <- [1, 4_999, 1] do
        {:ok, use} = Ruby.use_of_month(context.admin)
        words = RubyWords.use_warning(use.cost_microdollars, 2_000, month)
        assert words =~ "80% or more"
        assert Allowance.room?(context.organisation)

        used!(context, context.ana.id, 0, more)
      end

      # 20,000,000 millionths are the 20 dollars.
      {:ok, use} = Ruby.use_of_month(context.admin)
      assert use.cost_microdollars == 20_000_000
      assert RubyWords.use_warning(use.cost_microdollars, 2_000, month) =~ "is used"
      refute Allowance.room?(context.organisation)
    end

    test "a member who left stays in the counts, with a name that says so", context do
      used!(context, context.ana.id, 1, 50_000)

      :ok =
        Accounts.remove_member(context.ana_member,
          actor: context.root,
          tenant: context.organisation
        )

      # A row whose member is in no record of the organisation any more.
      used!(context, Ecto.UUID.generate(), 1, 20_000)

      context.conn
      |> visit(context.path)
      |> assert_has(
        members()
        |> row(~r/^#{email(context.ana)} \(former member\)\s.*about 0\.05$/s)
      )
      |> assert_has(members() |> row(~r/^A former member\s.*about 0\.02$/s))
    end

    test "a month with no use has no table", context do
      context.conn
      |> visit(context.path)
      |> assert_has(main() |> heading(level: 1), text: "Ruby")
      |> refute_has(main(), text: "US dollars used")
      |> refute_has(main() |> table("The replies and the cost of each member"))
    end

    test "nobody without the power settings reads it", context do
      used!(context, context.ana.id, 2, 3_000_000)

      build_conn()
      |> sign_in(context.ana)
      |> visit(context.path)
      |> assert_has(main(), text: "Your role does not have it.")
      |> refute_has(main(), text: "US dollars used")
      |> refute_has(main() |> table("The replies and the cost of each member"))

      # The policy leaves out each row for that person.
      assert {:ok, %{members: [], cost_microdollars: 0}} =
               Ruby.use_of_month(actor: context.ana, tenant: context.organisation)
    end
  end
end
