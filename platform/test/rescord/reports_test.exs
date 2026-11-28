defmodule Rescord.ReportsTest do
  @moduledoc """
  Holds the reports (ADR 0076): each action returns a PDF for a member of
  the organisation and for nobody else, it reads as that person, it renders
  with many records and with none, it refuses a day that is not right, and
  a person makes at most 30 in a minute.

  A test reads the title and the headings of a document in its bytes: Typst
  writes them as plain text. `RescordWeb.ReportWordsTest` holds the words of
  the rest.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.StorageFixtures

  alias AshTypst.Document
  alias Rescord.{Accounts, Reports, Residents}
  alias Rescord.Reports.{Facts, Report}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    disk_store!(tmp_dir)
    :ok
  end

  # Each report with the arguments that a test gives it.
  defp each_report(resident_id, options) do
    today = Accounts.today(options[:tenant])

    [
      resident_record:
        Reports.resident_record(resident_id, %{journal: :all, photos: true}, options),
      cage_card: Reports.cage_card(resident_id, options),
      register: Reports.register(options),
      movements: Reports.movements(Date.add(today, -90), today, options),
      task_sheet: Reports.task_sheet(options),
      stock: Reports.stock(options),
      housing: Reports.housing(options),
      expenses: Reports.expenses(Date.add(today, -90), today, options)
    ]
  end

  defp pdf!({:ok, %Document{format: :pdf, data: "%PDF-" <> _rest = pdf} = document}) do
    assert document.page_count >= 1
    assert document.warnings == []
    pdf
  end

  describe "the refuge Wattle Creek" do
    setup do
      {:ok, Rescord.ReportsFixtures.refuge!()}
    end

    test "a member makes each report, and each one names the refuge", context do
      reports = each_report(context.residents.biscuit.id, context.options)

      assert Keyword.keys(reports) == Reports.reports()

      titles = %{
        resident_record: "Record of Biscuit",
        cage_card: "Cage card of Biscuit",
        register: "Register of residents",
        movements: "Arrivals and departures",
        task_sheet: "Tasks of the day",
        stock: "Stock",
        housing: "Housing",
        expenses: "Expenses"
      }

      for {report, result} <- reports do
        pdf = pdf!(result)
        assert pdf =~ "#{titles[report]}, Wattle Creek", "the title of #{report}"
      end
    end

    test "the record holds the part of the journal that the person asks for", context do
      id = context.residents.biscuit.id

      medical = pdf!(Reports.resident_record(id, context.options))
      assert medical =~ "/Title(Medical history)"

      whole = pdf!(Reports.resident_record(id, %{journal: :all}, context.options))
      assert whole =~ "/Title(Journal)"

      none = pdf!(Reports.resident_record(id, %{journal: :none}, context.options))
      refute none =~ "/Title(Journal)"
      refute none =~ "/Title(Medical history)"
      refute none =~ "/Title(Photos)"

      with_photos = pdf!(Reports.resident_record(id, %{photos: true}, context.options))
      assert with_photos =~ "/Title(Photos)"
      assert byte_size(with_photos) > byte_size(medical)
    end

    test "an administrator and a member whose role has no power make the reports", context do
      assert {:ok, %Document{}} = Reports.stock(context.admin)

      {:ok, role} = Accounts.define_role(%{name: "Reader", powers: []}, context.admin)
      {member, reader} = member!(context.organisation, :member, context.administrator)
      {:ok, _member} = Accounts.set_member_role(member, role.id, context.admin)

      options = [actor: reader, tenant: context.organisation]
      assert {:ok, %Document{}} = Reports.register(options)
      assert {:ok, %Document{}} = Reports.cage_card(context.residents.biscuit.id, options)
    end

    test "nobody and a stranger make no report", context do
      stranger = user!()
      id = context.residents.biscuit.id

      for options <- [
            [actor: nil, tenant: context.organisation],
            [actor: stranger, tenant: context.organisation]
          ],
          {report, result} <- each_report(id, options) do
        assert {:error, %Ash.Error.Forbidden{}} = result,
               "#{report} for #{inspect(options[:actor])}"
      end

      for report <- Reports.reports() do
        refute Ash.can?({Report, report}, stranger, tenant: context.organisation)
      end
    end

    test "a report of another refuge holds no record of this one", context do
      other = organisation!(context.root, "Banksia Rise")
      {_, person} = member!(other, :administrator, context.root)
      options = [actor: person, tenant: other]
      id = context.residents.biscuit.id

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
               Reports.resident_record(id, options)

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
               Reports.cage_card(id, options)

      assert {:ok, %{rows: []}} = Facts.read(:register, %{}, options, DateTime.utc_now())
      assert {:ok, %{stock: []}} = Facts.read(:stock, %{}, options, DateTime.utc_now())

      # The same person cannot make a report in Wattle Creek.
      assert {:error, %Ash.Error.Forbidden{}} =
               Reports.register(actor: person, tenant: context.organisation)
    end

    test "the register of a day holds the residents that the refuge had then", context do
      now = DateTime.utc_now()
      names = fn facts -> facts.rows |> Enum.map(& &1.resident.name) |> Enum.sort() end

      {:ok, today} = Facts.read(:register, %{}, context.options, now)
      assert names.(today) == ~w(Biscuit Clover Hazel Juniper Pepper Pip Squeak)
      assert Enum.find(today.rows, &(&1.resident.name == "Juniper")).away?

      assert Enum.find(today.rows, &(&1.resident.name == "Biscuit")).homes == [
               ["Main shed", "Pen 3"]
             ]

      # Maple left 6 days ago, Juniper arrived 9 days ago, and Pip was born
      # in care 12 days ago.
      {:ok, before} =
        Facts.read(:register, %{on: Date.add(context.today, -15)}, context.options, now)

      assert "Maple" in names.(before)
      refute "Juniper" in names.(before)
      refute "Pip" in names.(before)

      # The records of that day held no placement yet: the test wrote each
      # one now.
      assert Enum.all?(before.rows, &(&1.homes == [] and not &1.away?))

      assert %Document{} =
               Reports.register!(%{on: Date.add(context.today, -15)}, context.options)
    end

    test "the arrivals and the departures add up", context do
      now = DateTime.utc_now()
      arguments = %{from: Date.add(context.today, -90), to: context.today}
      {:ok, facts} = Facts.read(:movements, arguments, context.options, now)

      assert length(facts.arrived) == 8
      assert Enum.map(facts.left, & &1.name) == ["Maple"]
      assert facts.at_start == 0
      assert facts.at_start + length(facts.arrived) - length(facts.left) == facts.at_end

      # Sorrel is expected, and has no arrival yet.
      refute "Sorrel" in Enum.map(facts.arrived, & &1.name)

      {:ok, later} =
        Facts.read(
          :movements,
          %{arguments | from: Date.add(context.today, -20)},
          context.options,
          now
        )

      assert later.at_start + length(later.arrived) - length(later.left) == later.at_end
      assert later.at_start == 4
    end
  end

  describe "a refuge with no record" do
    setup do
      root = root!()
      organisation = organisation!(root, "Wattle Creek")
      {_, member} = member!(organisation, :member, root)
      lists = lists!(organisation, root)

      {:ok,
       root: root,
       organisation: organisation,
       lists: lists,
       options: [actor: member, tenant: organisation],
       today: Accounts.today(organisation)}
    end

    test "each report of the refuge renders", context do
      for report <- [:register, :task_sheet, :stock, :housing] do
        assert "%PDF-" <> _rest = pdf!(apply(Reports, report, [context.options]))
      end

      pdf!(Reports.movements(Date.add(context.today, -30), context.today, context.options))
      pdf!(Reports.expenses(Date.add(context.today, -30), context.today, context.options))
    end

    test "the reports of a resident with few facts render", context do
      {:ok, resident} =
        Residents.register_resident(
          %{species_id: context.lists.species.guinea_pig, sex: :unknown},
          context.options
        )

      pdf =
        pdf!(
          Reports.resident_record(resident.id, %{journal: :all, photos: true}, context.options)
        )

      assert pdf =~ "Record of a resident with no name"
      pdf!(Reports.cage_card(resident.id, context.options))
    end

    test "the text of a record is never markup of Typst", context do
      # As markup, the first name stops the compiler and the second one reads a file.
      for name <- [~s|#panic("no")|, ~s|#read("/etc/hostname")|, "*Star* _and_ $x$ <tag> @ref"] do
        resident = resident!(context.lists, context.options, %{name: name})
        pdf!(Reports.resident_record(resident.id, context.options))
        pdf!(Reports.cage_card(resident.id, context.options))
      end

      pdf!(Reports.register(context.options))
      pdf!(Reports.housing(context.options))
    end

    test "a day that is not right is an error with words", context do
      tomorrow = Date.add(context.today, 1)

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Reports.register(%{on: tomorrow}, context.options)

      assert %Ash.Error.Action.InvalidArgument{field: :on, message: "is after today"} = error

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Reports.movements(context.today, Date.add(context.today, -1), context.options)

      assert %{field: :to, message: "is before the first day"} = error

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :to, message: "is after today"}]}} =
               Reports.movements(context.today, tomorrow, context.options)

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Reports.expenses(context.today, Date.add(context.today, -1), context.options)

      assert %{field: :to, message: "is before the first day"} = error

      # A period of the expenses can end after today: this year, for example.
      pdf!(Reports.expenses(context.today, tomorrow, context.options))

      # The tasks of tomorrow are a fair question.
      pdf!(Reports.task_sheet(%{on: tomorrow}, context.options))

      assert {:error, %Ash.Error.Invalid{}} =
               Reports.resident_record(Ash.UUID.generate(), %{journal: :nothing}, context.options)
    end

    test "a person makes 30 reports in a minute, in one count for all the reports", context do
      for number <- 1..30 do
        report = if rem(number, 2) == 0, do: :stock, else: :housing
        assert {:ok, %Document{}} = apply(Reports, report, [context.options])
      end

      assert {:error, %Ash.Error.Forbidden{errors: [%AshRateLimiter.LimitExceeded{limit: 30}]}} =
               Reports.register(context.options)

      # Another person has a count of their own.
      {_, other} = member!(context.organisation, :member, context.root)
      assert {:ok, %Document{}} = Reports.stock(actor: other, tenant: context.organisation)
    end
  end
end
