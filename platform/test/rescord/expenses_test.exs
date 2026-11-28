defmodule Rescord.ExpensesTest do
  @moduledoc """
  Holds the expenses of an organisation (`docs/domain.md`, section 5.10, and
  ADR 0082): who records one, who reads one, the amount as money in the
  currency of the organisation, the states from the record to the payment
  back, two people who decide at the same moment, the receipts, the sums
  and the history.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.StorageFixtures

  alias Rescord.{Accounts, Expenses}

  doctest Rescord.Expenses

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    disk_store!(tmp_dir)
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, sam} = member!(organisation, :member, administrator)
    {_, kim} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    admin = [actor: administrator, tenant: organisation]

    visitor_role = Accounts.define_role!(%{name: "Visitor", powers: []}, admin)
    {visitor_member, visitor} = member!(organisation, :member, administrator)
    Accounts.set_member_role!(visitor_member, visitor_role.id, admin)

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     sam: sam,
     kim: kim,
     visitor: visitor,
     stranger: user!(),
     lists: lists,
     admin: admin,
     options: [actor: sam, tenant: organisation],
     today: Accounts.today(organisation)}
  end

  defp facts(context, more \\ %{}) do
    Map.merge(
      %{
        paid_by: :member,
        amount: "186.00",
        incurred_on: context.today,
        payee: "Northside Vet Clinic",
        description: "Vet consult for Biscuit",
        category_id: context.lists.expense_category.veterinary
      },
      more
    )
  end

  defp submit!(context, more \\ %{}, options \\ nil),
    do: Expenses.submit_expense!(facts(context, more), options || context.options)

  defp as(context, user), do: [actor: user, tenant: context.organisation]

  defp fields(error), do: Enum.map(error.errors, &Map.get(&1, :field))

  describe "a new expense" do
    test "is money in the currency of the organisation, waits, and names who paid", context do
      expense = submit!(context)

      assert expense.amount == Money.new(:AUD, "186.00")
      assert expense.state == :submitted
      assert expense.author_id == context.sam.id
      assert expense.payer_id == context.sam.id
      assert expense.number >= 1

      second = submit!(context, %{paid_by: :organisation})
      assert second.number == expense.number + 1
      assert second.payer_id == nil
      assert second.state == :submitted
    end

    test "is in the new currency after the setting changes, and an old one keeps its own",
         context do
      old = submit!(context)

      organisation =
        Accounts.set_organisation_currency!(context.organisation, "JPY", context.admin)

      new = submit!(%{context | organisation: organisation}, %{amount: "1200"})
      assert new.amount == Money.new(:JPY, 1200)

      {:ok, old} = Expenses.expense(old.id, context.options)
      assert old.amount.currency == :AUD

      # A change of an old expense keeps its currency.
      revised = Expenses.revise_expense!(old, %{amount: "190.50"}, context.options)
      assert revised.amount == Money.new(:AUD, "190.50")

      # A yen has no decimal places.
      assert {:error, error} =
               Expenses.submit_expense(facts(context, %{amount: "12.5"}), context.options)

      assert :amount in fields(error)
    end

    test "refuses an amount that is no money of the currency", context do
      for amount <- ["0", "-5", "1.999", "100000000"] do
        assert {:error, error} =
                 Expenses.submit_expense(facts(context, %{amount: amount}), context.options)

        assert :amount in fields(error), "for #{amount}"
      end

      assert submit!(context, %{amount: "12.5"}).amount == Money.new(:AUD, "12.50")
      assert submit!(context, %{amount: "12.500"}).amount == Money.new(:AUD, "12.50")
    end

    test "refuses a date after today, a category of nowhere, and a resident of nowhere",
         context do
      assert {:error, error} =
               Expenses.submit_expense(
                 facts(context, %{incurred_on: Date.add(context.today, 1)}),
                 context.options
               )

      assert :incurred_on in fields(error)

      assert {:error, error} =
               Expenses.submit_expense(
                 facts(context, %{category_id: Ash.UUID.generate()}),
                 context.options
               )

      assert :category_id in fields(error)

      assert {:error, error} =
               Expenses.submit_expense(
                 facts(context, %{resident_id: Ash.UUID.generate()}),
                 context.options
               )

      assert :resident_id in fields(error)

      resident = resident!(context.lists, context.admin)
      expense = submit!(context, %{resident_id: resident.id})
      {:ok, [read]} = Expenses.report(%{resident_id: resident.id}, context.options)
      assert read.id == expense.id
      assert read.resident.name == "Biscuit"
      assert to_string(read.category.label) == "Veterinary"
    end

    test "takes no state, no author, no payer and no currency from the caller", context do
      for forged <- [
            %{state: :approved},
            %{author_id: context.kim.id},
            %{payer_id: context.kim.id},
            %{decided_by_id: context.kim.id},
            %{number: 7}
          ] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Expenses.submit_expense(facts(context, forged), context.options)
      end
    end

    test "a person who manages records one for another member, and one that the organisation paid",
         context do
      for_kim =
        Expenses.record_expense!(facts(context, %{payer_id: context.kim.id}), context.admin)

      assert for_kim.payer_id == context.kim.id
      assert for_kim.author_id == context.administrator.id
      assert for_kim.state == :submitted

      paid = Expenses.record_expense!(facts(context, %{paid_by: :organisation}), context.admin)
      assert paid.state == :approved
      assert paid.payer_id == nil
      assert paid.decided_by_id == context.administrator.id

      assert {:error, error} =
               Expenses.record_expense(
                 facts(context, %{payer_id: context.stranger.id}),
                 context.admin
               )

      assert :payer_id in fields(error)

      assert {:error, %Ash.Error.Forbidden{}} =
               Expenses.record_expense(
                 facts(context, %{payer_id: context.kim.id}),
                 context.options
               )
    end
  end

  describe "who reads and who writes" do
    test "a member reads their own, and a person who manages reads each one", context do
      mine = submit!(context)
      of_kim = submit!(context, %{}, as(context, context.kim))

      for_sam =
        Expenses.record_expense!(facts(context, %{payer_id: context.sam.id}), context.admin)

      ids = fn options -> options |> Expenses.expenses!() |> Enum.map(& &1.id) |> Enum.sort() end

      assert ids.(context.options) == Enum.sort([mine.id, for_sam.id])
      assert ids.(as(context, context.kim)) == [of_kim.id]
      assert ids.(context.admin) == Enum.sort([mine.id, of_kim.id, for_sam.id])
      assert ids.(as(context, context.root)) == Enum.sort([mine.id, of_kim.id, for_sam.id])
      # A role with no power still reads its own, and has none.
      assert ids.(as(context, context.visitor)) == []

      # A person who is no member, and nobody, read nothing.
      assert ids.(as(context, context.stranger)) == []
      assert ids.(tenant: context.organisation) == []

      assert {:ok, nil} = Expenses.expense(of_kim.id, context.options)
    end

    test "a role with no power, a stranger and nobody record nothing", context do
      for options <- [
            as(context, context.visitor),
            as(context, context.stranger),
            [tenant: context.organisation]
          ] do
        assert {:error, %Ash.Error.Forbidden{}} = Expenses.submit_expense(facts(context), options)
      end
    end

    test "a member changes and withdraws their own, and not the one of another member",
         context do
      mine = submit!(context)
      of_kim = submit!(context, %{}, as(context, context.kim))

      revised = Expenses.revise_expense!(mine, %{payee: "Southside Vet"}, context.options)
      assert revised.payee == "Southside Vet"

      assert {:error, %Ash.Error.Forbidden{}} =
               Expenses.revise_expense(of_kim, %{payee: "Mine now"}, context.options)

      assert {:error, %Ash.Error.Forbidden{}} = Expenses.withdraw_expense(of_kim, context.options)
      assert {:error, %Ash.Error.Forbidden{}} = Expenses.approve_expense(mine, context.options)

      assert {:error, %Ash.Error.Forbidden{}} =
               Expenses.decline_expense(mine, "No", context.options)

      assert :ok = Expenses.withdraw_expense(mine, context.options)
      assert {:ok, nil} = Expenses.expense(mine.id, context.admin)

      # A person who manages changes and withdraws each one.
      assert %{} = Expenses.revise_expense!(of_kim, %{note: "Checked"}, context.admin)
      assert :ok = Expenses.withdraw_expense(of_kim, context.admin)
    end
  end

  describe "the states" do
    test "approve, pay back, and open again", context do
      expense = submit!(context)

      approved = Expenses.approve_expense!(expense, context.admin)
      assert approved.state == :approved
      assert approved.decided_by_id == context.administrator.id
      assert %DateTime{} = approved.decided_at

      {:ok, [read]} = Expenses.report(%{status: :to_pay_back}, context.admin)
      assert read.id == expense.id
      assert read.status == :to_pay_back

      # A decided expense does not change, and is not withdrawn.
      assert {:error, _error} =
               Expenses.revise_expense(approved, %{note: "More"}, context.options)

      assert {:error, _error} = Expenses.withdraw_expense(approved, context.admin)

      assert {:error, error} =
               Expenses.reimburse_expense(
                 approved,
                 %{reimbursed_on: Date.add(context.today, 2)},
                 context.admin
               )

      assert :reimbursed_on in fields(error)

      paid =
        Expenses.reimburse_expense!(
          approved,
          %{reimbursement_reference: "Expense #{expense.number}"},
          context.admin
        )

      assert paid.state == :reimbursed
      assert paid.reimbursed_on == context.today
      assert paid.reimbursed_by_id == context.administrator.id

      opened = Expenses.reopen_expense!(paid, context.admin)
      assert opened.state == :submitted

      for field <- [:decided_by_id, :decided_at, :reimbursed_on, :reimbursed_by_id] do
        assert Map.fetch!(opened, field) == nil
      end
    end

    test "decline needs a reason, and the member changes the expense and sends it again",
         context do
      expense = submit!(context)

      assert {:error, error} = Expenses.decline_expense(expense, nil, context.admin)
      assert :decline_reason in fields(error)

      declined = Expenses.decline_expense!(expense, "The receipt is missing", context.admin)
      assert declined.state == :declined
      assert declined.decline_reason == "The receipt is missing"

      again = Expenses.revise_expense!(declined, %{note: "Receipt added"}, context.options)
      assert again.state == :submitted
      assert again.decline_reason == nil
      assert again.decided_by_id == nil
    end

    test "an expense that the organisation paid is not paid back", context do
      paid = Expenses.record_expense!(facts(context, %{paid_by: :organisation}), context.admin)
      assert {:error, _error} = Expenses.reimburse_expense(paid, %{}, context.admin)
    end

    test "two people decide at the same moment, and the second gets an error", context do
      expense = submit!(context)
      Expenses.approve_expense!(expense, context.admin)

      # The second person has the old record in hand.
      assert {:error, error} =
               Expenses.decline_expense(expense, "No", as(context, context.root))

      assert Enum.any?(error.errors, &match?(%Ash.Error.Changes.StaleRecord{}, &1))
    end

    test "a person approves their own expense", context do
      expense = submit!(context, %{}, context.admin)
      assert Expenses.approve_expense!(expense, context.admin).state == :approved
    end
  end

  describe "the receipts" do
    test "a photo loses its metadata and gets a thumbnail, and a PDF stays as it is", context do
      expense = submit!(context)

      photo =
        Expenses.attach_receipt!(
          %{expense_id: expense.id, name: "receipt.jpg", content: jpeg()},
          context.options
        )

      assert photo.content_type == "image/jpeg"
      assert photo.author_id == context.sam.id
      assert photo.key =~ "/receipts/#{photo.id}"
      assert photo.thumbnail_key =~ "/thumbnails/#{photo.id}"

      paper =
        Expenses.attach_receipt!(
          %{expense_id: expense.id, name: "invoice.pdf", content: pdf()},
          context.options
        )

      assert paper.content_type == "application/pdf"
      assert paper.thumbnail_key == nil

      assert {:ok, _receipt, bytes} = Expenses.receipt_file(paper.id, context.options)
      assert bytes == pdf()
      assert {:ok, _receipt, _bytes} = Expenses.receipt_thumbnail(photo.id, context.admin)
      assert {:error, :not_found} = Expenses.receipt_thumbnail(paper.id, context.options)

      {:ok, [read]} = Expenses.report(%{}, context.options)
      assert read.receipt_count == 2

      assert {:error, error} =
               Expenses.attach_receipt(
                 %{expense_id: expense.id, name: "notes.txt", content: "plain words"},
                 context.options
               )

      assert :content in fields(error)
    end

    test "another member neither reads a receipt nor adds one", context do
      expense = submit!(context)

      receipt =
        Expenses.attach_receipt!(
          %{expense_id: expense.id, name: "invoice.pdf", content: pdf()},
          context.options
        )

      kim = as(context, context.kim)
      assert {:error, :not_found} = Expenses.receipt_file(receipt.id, kim)
      assert {:ok, []} = Expenses.receipts(kim)

      assert {:error, error} =
               Expenses.attach_receipt(
                 %{expense_id: expense.id, name: "mine.pdf", content: pdf()},
                 kim
               )

      assert :expense_id in fields(error)

      assert {:error, %Ash.Error.Forbidden{}} =
               Expenses.attach_receipt(
                 %{expense_id: expense.id, name: "mine.pdf", content: pdf()},
                 as(context, context.visitor)
               )

      assert {:error, %Ash.Error.Forbidden{}} = Expenses.remove_receipt(receipt, kim)
    end

    test "a member takes off their own receipt until the decision", context do
      expense = submit!(context)

      attach = fn ->
        Expenses.attach_receipt!(
          %{expense_id: expense.id, name: "a.pdf", content: pdf()},
          context.options
        )
      end

      first = attach.()
      assert :ok = Expenses.remove_receipt(first, context.options)
      {:ok, [read]} = Expenses.report(%{}, context.options)
      assert read.receipt_count == 0

      second = attach.()
      Expenses.approve_expense!(expense, context.admin)
      assert {:error, _error} = Expenses.remove_receipt(second, context.options)
      assert {:error, %Ash.Error.Forbidden{}} = Expenses.discard_receipt(second, context.options)
      assert :ok = Expenses.discard_receipt(second, context.admin)

      # A proof of the payment can come after the decision.
      assert %{} = attach.()
    end
  end

  describe "what goes with an expense" do
    test "a withdrawn expense takes its receipts with it", context do
      expense = submit!(context)

      receipt =
        Expenses.attach_receipt!(
          %{expense_id: expense.id, name: "invoice.pdf", content: pdf()},
          context.options
        )

      assert :ok = Expenses.withdraw_expense(expense, context.options)
      assert {:ok, []} = Expenses.receipts(context.admin)
      assert {:error, :not_found} = Expenses.receipt_file(receipt.id, context.admin)
    end

    test "the export of the data holds the expenses, with an amount as two columns", context do
      expense = submit!(context)

      Expenses.attach_receipt!(
        %{expense_id: expense.id, name: "invoice.pdf", content: pdf()},
        context.options
      )

      {:ok, export} =
        Rescord.Export.export(context.organisation, context.today, actor: context.administrator)

      {:ok, files} = :zip.unzip(export.zip, [:memory])
      files = Map.new(files, fn {name, bytes} -> {Path.basename(to_string(name)), bytes} end)

      assert files["expenses.csv"] =~ "amount,amount_currency"
      assert files["expenses.csv"] =~ ",186.00,AUD,"
      assert files["expense_receipts.csv"] =~ "invoice.pdf"
      assert files["expense_categories.csv"] =~ "Veterinary"
      assert files["README.txt"] =~ "expense_receipts.csv lists"
    end
  end

  describe "the currency of an organisation" do
    test "is AUD at first, and changes for an administrator to a currency that people pay with",
         context do
      assert context.organisation.currency == "AUD"
      assert {"AUD", "Australian Dollar"} in Accounts.currencies()

      assert {:ok, %{currency: "NZD"}} =
               Accounts.set_organisation_currency(context.organisation, "NZD",
                 actor: context.administrator
               )

      for code <- ["XXX", "aud", "Dollars", "", nil] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Accounts.set_organisation_currency(context.organisation, code,
                   actor: context.root
                 ),
               "for #{inspect(code)}"
      end

      for actor <- [context.sam, context.visitor, context.stranger, nil] do
        assert {:error, %Ash.Error.Forbidden{}} =
                 Accounts.set_organisation_currency(context.organisation, "USD", actor: actor)
      end
    end
  end

  describe "the sums" do
    test "say what waits, what is to pay back and what was spent this month", context do
      submit!(context, %{amount: "10"})
      approved = submit!(context, %{amount: "20.50"})
      Expenses.approve_expense!(approved, context.admin)
      of_kim = submit!(context, %{amount: "5"}, as(context, context.kim))
      Expenses.approve_expense!(of_kim, context.admin)

      Expenses.record_expense!(
        facts(context, %{paid_by: :organisation, amount: "100"}),
        context.admin
      )

      long_ago = submit!(context, %{amount: "7", incurred_on: Date.add(context.today, -70)})
      Expenses.approve_expense!(long_ago, context.admin)

      Expenses.reimburse_expense!(
        Expenses.expense!(long_ago.id, context.admin),
        %{},
        context.admin
      )

      {:ok, all} = Expenses.figures(context.admin)
      assert all.waiting == %{count: 1, amounts: [Money.new(:AUD, "10.00")]}
      assert all.to_pay_back == %{count: 2, amounts: [Money.new(:AUD, "25.50")]}
      assert all.members == 2
      # The expense of 70 days ago is not of this month.
      assert all.spent == %{count: 3, amounts: [Money.new(:AUD, "125.50")]}
      assert all.month == Date.beginning_of_month(context.today)

      {:ok, own} = Expenses.figures(context.options)
      assert own.waiting.count == 1
      assert own.owed == %{count: 1, amounts: [Money.new(:AUD, "20.50")]}
      assert own.paid_back == %{count: 1, amounts: [Money.new(:AUD, "7.00")]}

      assert Expenses.sum([%{amount: Money.new(:AUD, 1)}, %{amount: Money.new(:JPY, 5)}]).amounts ==
               [Money.new(:AUD, 1), Money.new(:JPY, 5)]
    end

    test "the report holds the limits of the list", context do
      vet = submit!(context)

      feed =
        submit!(context, %{
          description: "Hay for a month",
          payee: "Creekside Produce",
          category_id: context.lists.expense_category.feed,
          incurred_on: Date.add(context.today, -10),
          paid_by: :organisation
        })

      ids = fn limits ->
        {:ok, expenses} = Expenses.report(limits, context.admin)
        Enum.map(expenses, & &1.id)
      end

      # The newest payment first.
      assert ids.(%{}) == [vet.id, feed.id]
      assert ids.(%{search: "creekside"}) == [feed.id]
      assert ids.(%{search: "VET"}) == [vet.id]
      assert ids.(%{category_id: context.lists.expense_category.feed}) == [feed.id]
      assert ids.(%{paid_by: :organisation}) == [feed.id]
      assert ids.(%{from: Date.add(context.today, -3)}) == [vet.id]
      assert ids.(%{to: Date.add(context.today, -3)}) == [feed.id]
      assert ids.(%{status: :submitted}) == [vet.id, feed.id]
      assert ids.(%{status: :declined}) == []
    end
  end

  describe "the history" do
    test "says what happened, the newest first, to a person who reads the expense", context do
      expense = submit!(context)

      receipt =
        Expenses.attach_receipt!(
          %{expense_id: expense.id, name: "invoice.pdf", content: pdf()},
          context.options
        )

      declined = Expenses.decline_expense!(expense, "Which resident?", context.admin)
      Expenses.revise_expense!(declined, %{amount: "190"}, context.options)
      Expenses.remove_receipt!(receipt, context.options)

      {:ok, events} = Expenses.history(expense.id, context.options)

      assert Enum.map(events, & &1.action) == [:take_off, :revise, :decline, :attach, :submit]

      assert Enum.map(events, & &1.user_id) ==
               [
                 context.sam.id,
                 context.sam.id,
                 context.administrator.id,
                 context.sam.id,
                 context.sam.id
               ]

      [take_off, _revise, decline, attach, _submit] = events
      assert take_off.changes["name"] == "invoice.pdf"
      assert attach.changes["name"] == "invoice.pdf"
      assert decline.changes["decline_reason"] == "Which resident?"

      assert {:error, :not_found} = Expenses.history(expense.id, as(context, context.kim))
    end
  end

  describe "what a page asks" do
    test "can?/4 follows the grant and the state", context do
      expense = submit!(context)
      member = Accounts.role_in(context.sam, member_of(context, context.sam))
      manager = Accounts.role_in(context.administrator, member_of(context, context.administrator))

      assert Expenses.can?(member, context.sam, expense, :revise)
      refute Expenses.can?(member, context.kim, expense, :revise)
      refute Expenses.can?(member, context.sam, expense, :approve)
      assert Expenses.can?(manager, context.administrator, expense, :approve)
      refute Expenses.can?(manager, context.administrator, expense, :reimburse)

      approved = Expenses.approve_expense!(expense, context.admin)
      refute Expenses.can?(member, context.sam, approved, :revise)
      assert Expenses.can?(manager, context.administrator, approved, :reimburse)
      assert Expenses.can?(:root, context.root, approved, :reopen)
      refute Expenses.can?(:root, context.root, approved, :approve)
    end
  end

  defp member_of(context, user) do
    {:ok, members} = Accounts.members([load: [:role]] ++ context.admin)
    Enum.find(members, &(&1.user_id == user.id))
  end
end
