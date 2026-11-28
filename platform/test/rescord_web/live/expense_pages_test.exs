defmodule RescordWeb.ExpensePagesTest do
  @moduledoc """
  Holds the pages of the expenses (ADR 0082): the list with its sums
  and its filters, the form with its receipts, the page of one expense with
  the decision and the payment, the files of the receipts, the CSV file,
  and the currency on the settings page.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import RescordWeb.Roles, only: [has?: 2, main: 0, alert: 1]
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.StorageFixtures

  alias Rescord.{Accounts, Expenses}
  alias RescordWeb.{ExpenseFileController, ExpenseWords}

  doctest ExpenseWords
  doctest ExpenseFileController

  @moduletag :tmp_dir

  setup %{conn: conn, tmp_dir: tmp_dir} do
    disk_store!(tmp_dir)
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root, "robin@example.org")
    {_, sam} = member!(organisation, :member, administrator, "sam@example.org")
    {_, kim} = member!(organisation, :member, administrator, "kim@example.org")
    lists = lists!(organisation, root)

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     sam: sam,
     kim: kim,
     lists: lists,
     admin: [actor: administrator, tenant: organisation],
     options: [actor: sam, tenant: organisation],
     today: Accounts.today(organisation),
     path: ~p"/o/#{organisation.short_name}/expenses",
     conn: sign_in(conn, sam),
     admin_conn: sign_in(build_conn(), administrator)}
  end

  defp open(conn, path) do
    {:ok, view, _html} = live(conn, path)
    {view, render_async(view)}
  end

  defp expense!(context, more \\ %{}, options \\ nil) do
    %{
      paid_by: :member,
      amount: "186.00",
      incurred_on: context.today,
      payee: "Northside Vet Clinic",
      description: "Vet consult for Biscuit",
      category_id: context.lists.expense_category.veterinary
    }
    |> Map.merge(more)
    |> Expenses.submit_expense!(options || context.options)
  end

  defp receipt!(context, expense, name \\ "invoice.pdf", content \\ nil) do
    Expenses.attach_receipt!(
      %{expense_id: expense.id, name: name, content: content || pdf()},
      context.options
    )
  end

  defp read!(context, expense), do: Expenses.expense!(expense.id, context.admin)

  test "the pages do not open for a user of another organisation, or with no sign-in", context do
    expense = expense!(context)
    other = organisation!(context.root, "Other")
    {_, outsider} = member!(other, :administrator, context.root)

    for path <- [
          context.path,
          context.path <> "/new",
          context.path <> "/#{expense.id}",
          context.path <> "/#{expense.id}/edit"
        ] do
      assert {:error, {:redirect, %{to: "/"}}} = build_conn() |> sign_in(outsider) |> live(path)
      assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), path)
    end
  end

  describe "the list" do
    test "shows a member their own expenses and their own sums", context do
      expense!(context)

      expense!(context, %{description: "Hay of Kim", amount: "40"},
        actor: context.kim,
        tenant: context.organisation
      )

      {view, html} = open(context.conn, context.path)

      assert html =~ "Vet consult for Biscuit"
      assert html =~ "Northside Vet Clinic"
      assert html =~ "$186.00"
      refute html =~ "Hay of Kim"
      assert has_element?(view, "dl[data-figures] dt", "To be paid back to you")
      refute has_element?(view, "dl[data-figures] dt", "To pay back")
      assert has_element?(view, "span[data-state=info]", "Waits for a decision")
      assert has_element?(view, "a[href$='/expenses/new']", "Record an expense")
    end

    test "shows a person who manages each expense, and the sums of the organisation", context do
      mine = expense!(context)
      Expenses.approve_expense!(mine, context.admin)

      expense!(context, %{description: "Hay of Kim", amount: "40"},
        actor: context.kim,
        tenant: context.organisation
      )

      {view, html} = open(context.admin_conn, context.path)

      assert html =~ "Vet consult for Biscuit"
      assert html =~ "Hay of Kim"
      assert html =~ "sam@example.org"
      assert has_element?(view, "dl[data-figures] dd[data-money]", "$40.00")
      assert has_element?(view, "dl[data-figures] dd", "1 expense of 1 member")
      assert has_element?(view, "span[data-state=info]", "To pay back")
    end

    test "shows at once what another person recorded and decided (ADR 0096)", context do
      {view, html} = open(context.admin_conn, context.path)
      refute html =~ "Hay of Kim"

      hay =
        expense!(context, %{description: "Hay of Kim", amount: "40"},
          actor: context.kim,
          tenant: context.organisation
        )

      # The sums are of the page, and the rows are of Cinder, which reads
      # them after the message.
      assert has_element?(view, "dl[data-figures] dd[data-money]", "$40.00")
      assert render_changes(view) =~ "Hay of Kim"

      # A member reads their own expenses alone, also after a change.
      {mine, _html} = open(context.conn, context.path)
      Expenses.approve_expense!(hay, context.admin)
      refute render_changes(mine) =~ "Hay of Kim"
      assert render_changes(view) =~ "To pay back"
    end

    test "holds the filters in its address, and the link to the CSV file carries them", context do
      expense!(context)
      declined = expense!(context, %{description: "Fuel"})
      Expenses.decline_expense!(declined, "No receipt", context.admin)

      {view, html} = open(context.conn, context.path <> "?status=declined")

      assert html =~ "Fuel"
      refute html =~ "Vet consult for Biscuit"
      assert has_element?(view, "p[data-downloads] a[href*='expenses.csv?status=declined']")

      # The report as PDF has a period: this month until today, or the dates
      # of the filter.
      today = Rescord.Accounts.today(context.organisation)
      month = "from=#{Date.beginning_of_month(today)}&to=#{today}"
      assert has_element?(view, "a#expenses-pdf[href$='reports/expenses.pdf?#{month}']")

      {view, _html} = open(context.conn, context.path <> "?incurred_on=2026-10-01,2026-10-31")

      assert has_element?(
               view,
               "a#expenses-pdf[href$='reports/expenses.pdf?from=2026-10-01&to=2026-10-31']",
               "Report of 1 October 2026 to 31 October 2026 as PDF"
             )
    end

    test "holds the expenses of one resident", context do
      biscuit = resident!(context.lists, context.admin)
      expense!(context, %{resident_id: biscuit.id})
      expense!(context, %{description: "Fuel"})

      {_view, html} = open(context.conn, context.path <> "?resident=#{biscuit.id}")

      assert html =~ "Only the expenses for"
      assert html =~ "Vet consult for Biscuit"
      refute html =~ "Fuel"
    end
  end

  describe "the form" do
    test "records an expense with a receipt, and it waits for a decision", context do
      {view, html} = open(context.conn, context.path <> "/new")

      assert html =~ "Amount, in Australian dollars"
      # A member names no other member.
      refute html =~ "Another member paid"

      upload =
        file_input(view, "#expense", :receipts, [
          %{name: "invoice.pdf", content: pdf(), type: "application/pdf"}
        ])

      assert render_upload(upload, "invoice.pdf") =~ "invoice.pdf"

      {:ok, view, _html} =
        view
        |> form("#expense",
          expense: %{
            paid_by: "member",
            amount: "58.25",
            incurred_on: Date.to_iso8601(context.today),
            payee: "Creekside Fuel",
            description: "Fuel for the transfer of Pip",
            category_id: context.lists.expense_category.transport
          }
        )
        |> render_submit()
        |> follow_redirect(context.conn)

      html = render(view)
      assert html =~ "The expense is recorded. It waits for a decision."
      assert html =~ "$58.25"
      assert html =~ "invoice.pdf"

      {:ok, [expense]} = Expenses.report(%{}, context.options)
      assert expense.amount == Money.new(:AUD, "58.25")
      assert expense.payer_id == context.sam.id
      assert expense.receipt_count == 1
    end

    test "says what is wrong, and keeps what the person typed", context do
      {view, _html} = open(context.conn, context.path <> "/new")

      html =
        view
        |> form("#expense",
          expense: %{
            amount: "12,50",
            incurred_on: Date.to_iso8601(context.today),
            payee: "Creekside Fuel",
            description: "Fuel",
            category_id: context.lists.expense_category.transport
          }
        )
        |> render_submit()

      # The layout always holds a hidden alert, so a search of the HTML for
      # the role finds one on each page: look in main, for one that shows.
      assert has?(view, main() |> alert())
      assert html =~ "Creekside Fuel"
      assert {:ok, []} = Expenses.report(%{}, context.options)
    end

    test "a person who manages records an expense of another member, and one of the organisation",
         context do
      {view, html} = open(context.admin_conn, context.path <> "/new")
      assert html =~ "Another member paid"

      facts = %{
        amount: "20",
        incurred_on: Date.to_iso8601(context.today),
        payee: "Creekside Produce",
        description: "Hay",
        category_id: context.lists.expense_category.feed
      }

      {:ok, _view, html} =
        view
        |> form("#expense",
          expense: Map.merge(facts, %{paid_by: "other", payer_id: context.kim.id})
        )
        |> render_submit()
        |> follow_redirect(context.admin_conn)

      assert html =~ "kim@example.org"

      {view, _html} = open(context.admin_conn, context.path <> "/new")

      {:ok, _view, html} =
        view
        |> form("#expense", expense: Map.put(facts, :paid_by, "organisation"))
        |> render_submit()
        |> follow_redirect(context.admin_conn)

      assert html =~ "The expense is recorded and approved."
    end

    test "changes an expense that was declined, and sends it again", context do
      expense = expense!(context)
      Expenses.decline_expense!(expense, "Which clinic?", context.admin)

      {view, html} = open(context.conn, context.path <> "/#{expense.id}/edit")
      assert html =~ "Which clinic?"
      assert html =~ ~s(value="186.00")

      {:ok, _view, html} =
        view
        |> form("#expense", expense: %{payee: "Southside Vet", amount: "190"})
        |> render_submit()
        |> follow_redirect(context.conn)

      assert html =~ "The expense is changed. It waits for a decision."
      assert read!(context, expense).state == :submitted
      assert read!(context, expense).payee == "Southside Vet"
    end

    test "does not open for an expense that is decided, or for the expense of another member",
         context do
      expense = expense!(context)
      Expenses.approve_expense!(expense, context.admin)

      assert {:error, {:redirect, %{to: to}}} =
               live(context.conn, context.path <> "/#{expense.id}/edit")

      assert to == context.path

      of_kim = expense!(context, %{}, actor: context.kim, tenant: context.organisation)

      assert {:error, {:redirect, %{to: ^to}}} =
               live(context.conn, context.path <> "/#{of_kim.id}/edit")

      assert {:error, {:redirect, %{to: ^to}}} =
               live(context.conn, context.path <> "/#{of_kim.id}")
    end
  end

  describe "the page of an expense" do
    test "shows the member the facts, and no decision", context do
      expense = expense!(context, %{note: "After hours"})
      receipt = receipt!(context, expense)

      {view, html} = open(context.conn, context.path <> "/#{expense.id}")

      assert html =~ "Expense #{expense.number}"
      assert html =~ "$186.00"
      assert html =~ "After hours"
      assert html =~ "recorded the expense."
      assert html =~ "added the receipt invoice.pdf."
      assert has_element?(view, "#receipt-#{receipt.id} a[href$='/receipts/#{receipt.id}']")
      assert has_element?(view, "a", "Change")
      refute has_element?(view, "#decision-heading")
      refute has_element?(view, "#payment-heading")
    end

    test "a person who manages approves, records the payment and opens the decision again",
         context do
      expense = expense!(context)
      path = context.path <> "/#{expense.id}"
      {view, _html} = open(context.admin_conn, path)

      {:ok, view, html} =
        view
        |> element("button", "Approve")
        |> render_click()
        |> follow_redirect(context.admin_conn)

      assert html =~ "The expense is approved."
      assert html =~ "To pay back"
      assert html =~ "Wattle Creek owes sam@example.org"

      {:ok, view, html} =
        view
        |> form("#reimburse",
          reimburse: %{on: Date.to_iso8601(context.today), reference: "EXP-1"}
        )
        |> render_submit()
        |> follow_redirect(context.admin_conn)

      assert html =~ "The payment is recorded."
      assert html =~ "Paid back"
      assert html =~ "with the reference EXP-1"
      assert read!(context, expense).state == :reimbursed

      {:ok, _view, html} =
        view
        |> element("#reopen-details button")
        |> render_click()
        |> follow_redirect(context.admin_conn)

      assert html =~ "The expense waits for a decision again."
      assert html =~ "opened the decision again."
      assert read!(context, expense).state == :submitted
    end

    test "a person who manages declines with a reason, which the member reads", context do
      expense = expense!(context)
      path = context.path <> "/#{expense.id}"
      {view, _html} = open(context.admin_conn, path)

      {:ok, _view, html} =
        view
        |> form("#decline", decline: %{reason: "The receipt is missing"})
        |> render_submit()
        |> follow_redirect(context.admin_conn)

      assert html =~ "The expense is declined."

      {_view, html} = open(context.conn, path)
      assert html =~ "declined the expense: The receipt is missing"
      assert html =~ "Declined"
    end

    test "says so when another person decided a moment before", context do
      expense = expense!(context)
      {view, _html} = open(context.admin_conn, context.path <> "/#{expense.id}")
      Expenses.decline_expense!(expense, "No", actor: context.root, tenant: context.organisation)

      {:ok, _view, html} =
        view
        |> element("button", "Approve")
        |> render_click()
        |> follow_redirect(context.admin_conn)

      assert html =~ "Another person changed the expense a moment ago."
      assert read!(context, expense).state == :declined
    end

    test "the member adds a receipt and takes it off, and withdraws the expense", context do
      expense = expense!(context)
      path = context.path <> "/#{expense.id}"
      {view, _html} = open(context.conn, path)

      upload =
        file_input(view, "#add-receipt", :receipts, [
          %{name: "receipt.jpg", content: photo(gps: true), type: "image/jpeg"}
        ])

      render_upload(upload, "receipt.jpg")

      {:ok, view, html} =
        view |> form("#add-receipt") |> render_submit() |> follow_redirect(context.conn)

      assert html =~ "The receipt is added."
      {:ok, [receipt]} = Expenses.receipts_of(expense.id, context.options)

      assert has_element?(
               view,
               "#receipt-#{receipt.id} img[src$='/receipts/#{receipt.id}/thumbnail']"
             )

      {:ok, view, html} =
        view
        |> element("#receipt-#{receipt.id} button")
        |> render_click()
        |> follow_redirect(context.conn)

      assert html =~ "The receipt is taken off."
      assert html =~ "The expense has no receipt."

      {:ok, _view, html} =
        view |> element("button", "Withdraw") |> render_click() |> follow_redirect(context.conn)

      assert html =~ "The expense is withdrawn."
      assert {:ok, nil} = Expenses.expense(expense.id, context.admin)
    end

    test "says why a file did not go in", context do
      expense = expense!(context)
      {view, _html} = open(context.conn, context.path <> "/#{expense.id}")

      upload =
        file_input(view, "#add-receipt", :receipts, [
          %{name: "fake.pdf", content: "not a file that Rescord takes", type: "application/pdf"}
        ])

      render_upload(upload, "fake.pdf")

      {:ok, _view, html} =
        view |> form("#add-receipt") |> render_submit() |> follow_redirect(context.conn)

      assert html =~ "fake.pdf"
      assert html =~ "is not a photo or a PDF"
      assert {:ok, []} = Expenses.receipts_of(expense.id, context.options)
    end
  end

  describe "the file of a receipt" do
    test "goes to the person of the expense and to a person who manages, in a sandbox", context do
      expense = expense!(context)
      paper = receipt!(context, expense)
      photo = receipt!(context, expense, "receipt.jpg", jpeg())
      base = "/o/#{context.organisation.short_name}/receipts"

      for conn <- [context.conn, context.admin_conn] do
        conn = get(conn, "#{base}/#{paper.id}")
        assert response(conn, 200) == pdf()
        assert get_resp_header(conn, "content-type") == ["application/pdf"]
        assert get_resp_header(conn, "cache-control") == [RescordWeb.FileCache.kept()]
        assert [policy] = get_resp_header(conn, "content-security-policy")
        assert policy =~ "sandbox"
        assert [disposition] = get_resp_header(conn, "content-disposition")
        assert disposition =~ ~s(filename="invoice.pdf")
      end

      conn = get(context.conn, "#{base}/#{photo.id}/thumbnail")
      assert response(conn, 200)
      assert get_resp_header(conn, "content-type") == ["image/webp"]

      # A PDF has no thumbnail.
      assert get(context.conn, "#{base}/#{paper.id}/thumbnail").status == 404
    end

    test "does not go to another member, to an outsider, or with no sign-in", context do
      expense = expense!(context)
      receipt = receipt!(context, expense)
      path = ~p"/o/#{context.organisation.short_name}/receipts/#{receipt.id}"
      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)

      assert get(sign_in(build_conn(), context.kim), path).status == 404
      assert get(sign_in(build_conn(), outsider), path).status == 404
      assert get(build_conn(), path).status in [302, 404]
      assert get(context.conn, path <> "x").status == 404
    end
  end

  describe "the CSV file" do
    test "holds the expenses of the list, with words, a number and the code of the currency",
         context do
      biscuit = resident!(context.lists, context.admin)
      expense = expense!(context, %{resident_id: biscuit.id, description: "=SUM(A1) consult"})
      receipt!(context, expense)
      Expenses.approve_expense!(expense, context.admin)
      expense!(context, %{description: "Fuel"}, actor: context.kim, tenant: context.organisation)

      conn = get(context.admin_conn, context.path <> ".csv")
      body = response(conn, 200)
      assert [type] = get_resp_header(conn, "content-type")
      assert type =~ "text/csv"
      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "expenses-#{context.organisation.short_name}-"

      assert "﻿" <> csv = body
      [header | rows] = String.split(csv, "\r\n", trim: true)
      assert header == Enum.join(ExpenseWords.csv_header(), ",")
      assert length(rows) == 2

      row = Enum.find(rows, &(&1 =~ "consult"))
      # A text that a spreadsheet would run as a formula has a ' before it.
      assert row =~ "'=SUM(A1) consult"

      assert row =~
               ",Northside Vet Clinic,Veterinary,Biscuit,member,sam@example.org,186.00,,AUD,To pay back,"

      assert row =~ "robin@example.org"
      assert String.ends_with?(row, ",1")

      # The limits of the list hold the file too.
      limited = response(get(context.admin_conn, context.path <> ".csv?status=to_pay_back"), 200)
      assert limited =~ "consult"
      refute limited =~ "Fuel"

      # A member gets their own expenses.
      own = response(get(context.conn, context.path <> ".csv"), 200)
      assert own =~ "consult"
      refute own =~ "Fuel"
    end

    test "does not go to an outsider, or with no sign-in", context do
      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)

      assert get(sign_in(build_conn(), outsider), context.path <> ".csv").status == 404
      assert get(build_conn(), context.path <> ".csv").status in [302, 404]
    end
  end

  describe "the tax in the amount" do
    defp name_the_tax!(context, name \\ "GST") do
      Accounts.set_organisation_tax_name!(context.organisation, name,
        actor: context.administrator
      )
    end

    test "an administrator names the tax on the settings page, and a member only reads it",
         context do
      path = ~p"/o/#{context.organisation.short_name}/settings"

      {view, html} = open(context.conn, path)
      assert html =~ "The expenses record no tax."
      refute has_element?(view, "#tax-name")

      {view, _html} = open(context.admin_conn, path)

      {:ok, view, html} =
        view
        |> form("#tax-name", tax: %{name: " GST "})
        |> render_submit()
        |> follow_redirect(context.admin_conn)

      assert html =~ "An expense can hold its GST now."
      assert has_element?(view, "#tax-name-text[value=GST]")

      # A name that is too long stays out, and the page says why.
      html =
        render_submit(view, "save_tax_name", %{"tax" => %{"name" => "Goods and services tax"}})

      assert html =~ "12"
      assert Accounts.tax_name_of("org_#{context.organisation.id}") == "GST"

      {:ok, _view, html} =
        view
        |> form("#tax-name", tax: %{name: ""})
        |> render_submit()
        |> follow_redirect(context.admin_conn)

      assert html =~ "The expenses record no tax now."
    end

    test "the form has the field only while the organisation names a tax", context do
      {view, html} = open(context.conn, context.path <> "/new")
      refute html =~ "in the amount (optional)"
      refute has_element?(view, "#expense input[name='expense[tax]']")

      name_the_tax!(context)
      {view, html} = open(context.conn, context.path <> "/new")
      assert html =~ "GST in the amount (optional)"

      fields = %{
        paid_by: "member",
        amount: "58.25",
        tax: "60",
        incurred_on: Date.to_iso8601(context.today),
        payee: "Creekside Fuel",
        description: "Fuel for the transfer of Pip",
        category_id: context.lists.expense_category.transport
      }

      html = view |> form("#expense", expense: fields) |> render_submit()
      assert html =~ "must not be more than the amount"
      assert html =~ ~s(value="60")

      {:ok, view, _html} =
        view
        |> form("#expense", expense: %{fields | tax: "5.30"})
        |> render_submit()
        |> follow_redirect(context.conn)

      html = render(view)
      assert html =~ "GST in the amount"
      assert html =~ "$5.30"
      # A member does not correct the tax of a decided expense.
      refute has_element?(view, "#tax")

      {:ok, [expense]} = Expenses.report(%{}, context.options)
      assert Money.equal?(expense.tax, Money.new(:AUD, "5.30"))

      # The form of a change holds the tax, and an empty field clears it.
      {view, html} = open(context.conn, context.path <> "/#{expense.id}/edit")
      assert html =~ ~s(value="5.30")

      {:ok, _view, _html} =
        view
        |> form("#expense", expense: %{tax: ""})
        |> render_submit()
        |> follow_redirect(context.conn)

      assert read!(context, expense).tax == nil
    end

    test "a person who manages corrects the tax of a decided expense", context do
      expense = expense!(context)
      Expenses.approve_expense!(expense, context.admin)
      path = context.path <> "/#{expense.id}"

      # With no name of a tax, the page has no tax.
      {view, html} = open(context.admin_conn, path)
      refute has_element?(view, "#tax")
      refute html =~ "in the amount"

      name_the_tax!(context)
      {view, _html} = open(context.admin_conn, path)
      assert has_element?(view, "#tax-details summary", "Correct the GST")

      html = view |> form("#tax", tax: %{amount: "200"}) |> render_submit()
      assert html =~ "must not be more than the amount"

      {:ok, view, html} =
        view
        |> form("#tax", tax: %{amount: "16.91"})
        |> render_submit()
        |> follow_redirect(context.admin_conn)

      assert html =~ "The tax in the amount is saved."
      assert html =~ "$16.91"
      assert html =~ "corrected the tax in the amount."
      assert has_element?(view, "#tax-amount[value='16.91']")

      expense = read!(context, expense)
      assert Money.equal?(expense.tax, Money.new(:AUD, "16.91"))
      assert expense.state == :approved

      # The member of the expense reads the tax, and has no form for it.
      {view, html} = open(context.conn, path)
      assert html =~ "GST in the amount"
      assert html =~ "$16.91"
      refute has_element?(view, "#tax")

      # The CSV file has the tax as a number, between the amount and the currency.
      csv = response(get(context.admin_conn, context.path <> ".csv"), 200)
      assert csv =~ ",186.00,16.91,AUD,To pay back,"
    end
  end

  describe "the currency on the settings page" do
    test "an administrator changes it, and a member only reads it", context do
      path = ~p"/o/#{context.organisation.short_name}/settings"

      {view, html} = open(context.conn, path)
      assert html =~ "Australian Dollar (AUD)"
      refute has_element?(view, "#currency")

      {view, _html} = open(context.admin_conn, path)

      {:ok, _view, html} =
        view
        |> form("#currency", currency: %{code: "NZD"})
        |> render_submit()
        |> follow_redirect(context.admin_conn)

      assert html =~ "A new expense is in NZD now."
      assert html =~ "New Zealand Dollar (NZD)"
    end
  end
end
