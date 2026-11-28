defmodule RescordWeb.ExpenseComponents do
  @moduledoc """
  The parts of the pages of the expenses (ADR 0082): the sums at the top
  of the list, the fields of the form, the card of one expense with its
  decision, its payment, its receipts and what happened to it, and the
  setting of the currency.

  Each part is a function component with no class: the stylesheet finds it
  by its element and by a `data-` attribute.
  """

  use RescordWeb, :html

  alias RescordWeb.{ExpenseWords, ResidentWords, UploadWords}

  @doc """
  The three sums at the top of the list. A person who manages the expenses
  gets the sums of the organisation, and each other person gets their own.
  """
  attr :figures, :map, required: true
  attr :manage?, :boolean, required: true
  attr :currency, :string, required: true

  def figures(assigns) do
    ~H"""
    <dl data-figures aria-label="Sums">
      <div>
        <dt><.icon name="clock" /> Wait for a decision</dt>
        <dd data-money>{ExpenseWords.amounts(@figures.waiting, @currency)}</dd>
        <dd>{ExpenseWords.count(@figures.waiting.count, "expense")}</dd>
      </div>
      <div :if={@manage?}>
        <dt><.icon name="banknotes" /> To pay back</dt>
        <dd data-money>{ExpenseWords.amounts(@figures.to_pay_back, @currency)}</dd>
        <dd>
          {ExpenseWords.count(@figures.to_pay_back.count, "expense")} of {ExpenseWords.count(
            @figures.members,
            "member"
          )}
        </dd>
      </div>
      <div :if={@manage?}>
        <dt><.icon name="calendar" /> Spent in {ExpenseWords.month(@figures.month)}</dt>
        <dd data-money>{ExpenseWords.amounts(@figures.spent, @currency)}</dd>
        <dd>{ExpenseWords.count(@figures.spent.count, "expense")}, approved or paid back</dd>
      </div>
      <div :if={!@manage?}>
        <dt><.icon name="banknotes" /> To be paid back to you</dt>
        <dd data-money>{ExpenseWords.amounts(@figures.owed, @currency)}</dd>
        <dd>{ExpenseWords.count(@figures.owed.count, "expense")}</dd>
      </div>
      <div :if={!@manage?}>
        <dt><.icon name="check" /> Paid back to you in {ExpenseWords.month(@figures.month)}</dt>
        <dd data-money>{ExpenseWords.amounts(@figures.paid_back, @currency)}</dd>
        <dd>{ExpenseWords.count(@figures.paid_back.count, "expense")}</dd>
      </div>
    </dl>
    """
  end

  @doc """
  The fields of the form of an expense. A new expense asks who paid; a
  change does not, because that does not change. `payers` is the list of
  the members for a person who records an expense that another member
  paid, or empty.
  """
  attr :form, :any, required: true
  attr :new?, :boolean, required: true
  attr :organisation, :any, required: true
  attr :currency, :string, required: true
  attr :tax_name, :any, default: nil
  attr :payers, :list, required: true
  attr :categories, :list, required: true
  attr :residents, :list, required: true
  attr :max_date, :string, required: true

  def expense_fields(assigns) do
    ~H"""
    <fieldset :if={@new?}>
      <legend>Who paid?</legend>
      <label>
        <input
          type="radio"
          name="expense[paid_by]"
          value="member"
          checked={@form[:paid_by].value not in ["organisation", "other"]}
        /> I paid, and {@organisation.name} pays me back
      </label>
      <label>
        <input
          type="radio"
          name="expense[paid_by]"
          value="organisation"
          checked={@form[:paid_by].value == "organisation"}
        />
        {@organisation.name} paid
      </label>
      <label :if={@payers != []}>
        <input
          type="radio"
          name="expense[paid_by]"
          value="other"
          checked={@form[:paid_by].value == "other"}
        /> Another member paid
      </label>
      <.input
        :if={@payers != []}
        field={@form[:payer_id]}
        type="select"
        label="The member who paid, for an expense of another member"
        prompt="Choose a member"
        options={@payers}
      />
    </fieldset>
    <.input
      field={@form[:amount]}
      label={"Amount, in #{ExpenseWords.currency_plural(@currency)}"}
      inputmode="decimal"
      autocomplete="off"
      hint="The whole amount on the receipt, with its tax."
      required
    />
    <.input
      :if={@tax_name}
      field={@form[:tax]}
      label={"#{@tax_name} in the amount (optional)"}
      inputmode="decimal"
      autocomplete="off"
      hint={"The part of the amount that is #{@tax_name}, from the receipt. Leave it empty when the receipt shows none."}
    />
    <.input
      field={@form[:incurred_on]}
      type="date"
      label="Date of the payment"
      max={@max_date}
      required
    />
    <.input
      field={@form[:payee]}
      label="Paid to"
      hint="The shop, the clinic or the person."
      maxlength="120"
      required
    />
    <.input field={@form[:description]} label="What it was for" maxlength="200" required />
    <.input
      field={@form[:category_id]}
      type="select"
      label="Category"
      prompt="Choose a category"
      options={@categories}
      required
    />
    <.input
      field={@form[:resident_id]}
      type="select"
      label="Resident (optional)"
      prompt="No resident in particular"
      options={@residents}
      hint="When the expense was for one resident."
    />
    <.input
      field={@form[:note]}
      type="textarea"
      label="Note (optional)"
      rows="3"
      maxlength="1000"
    />
    """
  end

  @doc """
  The control that takes the files of the receipts, with each chosen file,
  how much of it has arrived, and a button that takes it out.
  """
  attr :upload, :any, required: true

  def receipt_files(assigns) do
    ~H"""
    <fieldset id="receipt-files">
      <legend>Receipts</legend>
      <label for={@upload.ref}>Choose files, or take a photo</label>
      <.live_file_input upload={@upload} aria-describedby="receipt-files-hint" />
      <small id="receipt-files-hint">
        A photo or a PDF, five at most, each 20 MB at most. Rescord removes the place and the
        other metadata of a photo before it keeps it.
      </small>
      <p :for={error <- upload_errors(@upload)} role="alert">{upload_words(error)}</p>
      <ul :if={@upload.entries != []}>
        <li :for={entry <- @upload.entries} id={"new-receipt-#{entry.ref}"}>
          <span>{entry.client_name}</span>
          <progress value={entry.progress} max="100" aria-label={"Sent of #{entry.client_name}"}>
            {entry.progress} percent
          </progress>
          <span :for={error <- upload_errors(@upload, entry)} role="alert">
            {UploadWords.of(error, entry, &upload_words/1)}
          </span>
          <.button
            type="button"
            phx-click="cancel_receipt"
            phx-value-ref={entry.ref}
            aria-label={"Take out #{entry.client_name}"}
          >
            <.icon name="x-mark" /> Take out
          </.button>
        </li>
      </ul>
    </fieldset>
    """
  end

  @doc "The words of a problem of a file that the browser sends."
  def upload_words(:too_large), do: "The file is more than 20 MB."

  def upload_words(:not_accepted),
    do: "Rescord takes a photo or a PDF: JPEG, PNG, GIF, WebP or PDF."

  def upload_words(:too_many_files), do: "Choose five files at most."
  def upload_words(_other), do: "The file did not arrive. Choose it again."

  @doc "The card of one expense: its amount and its state, then its facts."
  attr :expense, :any, required: true
  attr :organisation, :any, required: true
  attr :people, :map, required: true

  def expense_card(assigns) do
    ~H"""
    <article data-expense>
      <p>
        <span data-money>{ExpenseWords.money(@expense.amount)}</span>
        <.state kind={ExpenseWords.status_kind(@expense.status)}>
          {ExpenseWords.status(@expense.status)}
        </.state>
      </p>
      <p :if={@expense.state == :declined && @expense.decline_reason} role="status">
        {ExpenseWords.person(@people, @expense.decided_by_id)} declined the expense: {@expense.decline_reason}
      </p>
      <.list>
        <:item title="Paid by">
          {ExpenseWords.paid_by(@expense, @organisation, @people)}{if @expense.status ==
                                                                        :to_pay_back,
                                                                      do: ", to pay back"}
        </:item>
        <:item title="Paid to">{@expense.payee}</:item>
        <:item :if={@expense.tax} title={"#{ExpenseWords.tax_name(@organisation)} in the amount"}>
          <span data-money>{ExpenseWords.money(@expense.tax)}</span>
        </:item>
        <:item title="Date">{ResidentWords.date(@expense.incurred_on)}</:item>
        <:item title="Category">
          {if @expense.category, do: @expense.category.label, else: "A category that is gone"}
        </:item>
        <:item :if={@expense.resident} title="Resident">
          <.link navigate={~p"/o/#{@organisation.short_name}/residents/#{@expense.resident.id}"}>
            {@expense.resident.name || "A resident with no name"}
          </.link>
        </:item>
        <:item :if={@expense.note} title="Note">{@expense.note}</:item>
        <:item :if={@expense.state == :reimbursed} title="Paid back">
          {ResidentWords.date(@expense.reimbursed_on)}{if @expense.reimbursement_reference,
            do: ", with the reference #{@expense.reimbursement_reference}"}
        </:item>
        <:item
          :if={
            ExpenseWords.person(@people, @expense.author_id) !=
              ExpenseWords.paid_by(@expense, @organisation, @people)
          }
          title="Recorded by"
        >
          {ExpenseWords.person(@people, @expense.author_id)}
        </:item>
      </.list>
    </article>
    """
  end

  @doc "The decision of an expense that waits: a button that approves, and a form that declines."
  attr :expense, :any, required: true
  attr :people, :map, required: true
  attr :can, :map, required: true

  def decision(assigns) do
    ~H"""
    <section :if={@can.approve? or @can.decline?} aria-labelledby="decision-heading">
      <h2 id="decision-heading">Decision</h2>
      <p :if={@can.approve?}>
        <.button type="button" variant="primary" phx-click="approve"><.icon name="check" /> Approve</.button>
      </p>
      <details :if={@can.decline?} id="decline-details">
        <summary><.icon name="x-circle" /> Decline</summary>
        <form id="decline" phx-submit="decline">
          <.input
            id="decline-reason"
            name="decline[reason]"
            type="textarea"
            label="Reason"
            value=""
            rows="2"
            maxlength="500"
            hint={"#{ExpenseWords.person(@people, @expense.author_id)} reads the reason, and can change the expense and send it again."}
            required
          />
          <footer><.button type="submit">Decline the expense</.button></footer>
        </form>
      </details>
    </section>
    """
  end

  @doc """
  The form that corrects the tax in the amount of an expense, for a person
  who manages the expenses, while the organisation names a tax. It changes
  nothing else of the expense.
  """
  attr :expense, :any, required: true
  attr :organisation, :any, required: true
  attr :can, :map, required: true

  def tax_correction(assigns) do
    ~H"""
    <details :if={@can.set_tax? and @organisation.tax_name} id="tax-details">
      <summary><.icon name="pencil" /> Correct the {@organisation.tax_name}</summary>
      <form id="tax" phx-submit="set_tax">
        <.input
          id="tax-amount"
          name="tax[amount]"
          label={"#{@organisation.tax_name} in the amount, in #{ExpenseWords.currency_plural(@expense.amount.currency)}"}
          inputmode="decimal"
          autocomplete="off"
          value={if @expense.tax, do: ExpenseWords.plain(@expense.tax), else: ""}
          hint="Leave it empty for an expense with none. The amount and the decision stay as they are."
        />
        <footer><.button type="submit">Save the {@organisation.tax_name}</.button></footer>
      </form>
    </details>
    """
  end

  @doc """
  The payment back to the member: the form that records it for an approved
  expense, and the button that opens a decision again.
  """
  attr :expense, :any, required: true
  attr :organisation, :any, required: true
  attr :people, :map, required: true
  attr :can, :map, required: true
  attr :max_date, :string, required: true

  def payment(assigns) do
    ~H"""
    <section :if={@can.reimburse? or @can.reopen?} aria-labelledby="payment-heading">
      <h2 id="payment-heading">
        <.icon :if={@can.reimburse?} name="banknotes" /> {if @can.reimburse?,
          do: "Payment",
          else: "Decision"}
      </h2>
      <p :if={@can.reimburse?}>
        {@organisation.name} owes {ExpenseWords.person(@people, @expense.payer_id)}
        <span data-money>{ExpenseWords.money(@expense.amount)}</span>. Rescord sends no money: record the payment here after you make it.
      </p>
      <form :if={@can.reimburse?} id="reimburse" phx-submit="reimburse">
        <.input
          id="reimburse-on"
          name="reimburse[on]"
          type="date"
          label="Date of the payment"
          value={@max_date}
          max={@max_date}
          required
        />
        <.input
          id="reimburse-reference"
          name="reimburse[reference]"
          label="Reference (optional)"
          value=""
          maxlength="120"
          hint="For example the words of the bank transfer."
        />
        <footer><.button type="submit">Record the payment</.button></footer>
      </form>
      <details :if={@can.reopen?} id="reopen-details">
        <summary><.icon name="arrow-uturn-left" /> Open the decision again</summary>
        <p>
          The expense then waits for a decision again, with no decision and no payment. What
          happened stays in the list below.
        </p>
        <.button type="button" phx-click="reopen">Open the decision again</.button>
      </details>
    </section>
    """
  end

  @doc "The receipts of an expense as a grid of tiles, and the form that adds one."
  attr :expense, :any, required: true
  attr :receipts, :list, required: true
  attr :organisation, :any, required: true

  attr :removable, :any,
    required: true,
    doc: "the ids of the receipts that the person can take off"

  attr :upload, :any, default: nil
  attr :problems, :list, default: []

  def receipts(assigns) do
    ~H"""
    <section aria-labelledby="receipts-heading">
      <h2 id="receipts-heading"><.icon name="paper-clip" /> Receipts</h2>
      <p :if={@receipts == []}>The expense has no receipt.</p>
      <ul :if={@receipts != []} data-receipts>
        <li :for={receipt <- @receipts} id={"receipt-#{receipt.id}"}>
          <a
            href={~p"/o/#{@organisation.short_name}/receipts/#{receipt.id}"}
            target="_blank"
            aria-label={!receipt.thumbnail_key && "#{receipt.name}, #{file_word(receipt)}"}
          >
            <img
              :if={receipt.thumbnail_key}
              src={~p"/o/#{@organisation.short_name}/receipts/#{receipt.id}/thumbnail"}
              alt={"#{receipt.name}, a photo"}
              loading="lazy"
              width="320"
              height="320"
            />
            <span :if={!receipt.thumbnail_key} data-file><.icon name="document-text" /> {file_word(
              receipt
            )}</span>
          </a>
          <small>{receipt.name} · {ExpenseWords.size(receipt.size)}</small>
          <.button
            :if={MapSet.member?(@removable, receipt.id)}
            type="button"
            phx-click="take_off"
            phx-value-id={receipt.id}
            data-confirm={"Take #{receipt.name} off the expense?"}
            aria-label={"Take off #{receipt.name}"}
          >
            <.icon name="x-mark" /> Take off
          </.button>
        </li>
      </ul>
      <details :if={@upload} id="add-receipt-details" open={@problems != []}>
        <summary><.icon name="arrow-up-tray" /> Add a receipt</summary>
        <form id="add-receipt" phx-submit="attach" phx-change="choose">
          <.problems list={@problems} />
          <.receipt_files upload={@upload} />
          <footer><.button type="submit">Add the receipts</.button></footer>
        </form>
      </details>
    </section>
    """
  end

  defp file_word(%{content_type: "application/pdf"}), do: "PDF"
  defp file_word(_photo), do: "Photo"

  @doc "What happened to an expense, the newest first."
  attr :events, :list, required: true
  attr :organisation, :any, required: true
  attr :people, :map, required: true

  def history(assigns) do
    ~H"""
    <section aria-labelledby="history-heading">
      <h2 id="history-heading">What happened</h2>
      <ol data-history>
        <li :for={event <- @events}>
          <time datetime={DateTime.to_iso8601(event.at)}>
            {ExpenseWords.instant(@organisation, event.at)}
          </time>
          {ExpenseWords.person(@people, event.user_id)} {ExpenseWords.event(event)}
        </li>
      </ol>
    </section>
    """
  end

  @doc """
  The name of the tax that an expense of an organisation can hold, and the
  form that changes it. With no name, the expenses record no tax.
  """
  attr :organisation, :any, required: true
  attr :can_change?, :any, required: true

  def tax_setting(assigns) do
    ~H"""
    <section aria-labelledby="tax-heading">
      <h2 id="tax-heading"><.icon name="banknotes" /> Tax</h2>
      <p :if={@organisation.tax_name}>
        An expense can hold the <strong>{@organisation.tax_name}</strong>
        in its amount, as the receipt shows it. Rescord knows no rate.
      </p>
      <p :if={!@organisation.tax_name}>
        The expenses record no tax. Give the name of a tax, and an expense can hold the part of its amount that is that tax.
      </p>
      <form :if={@can_change?} id="tax-name" phx-submit="save_tax_name">
        <.input
          id="tax-name-text"
          name="tax[name]"
          label="Name of the tax"
          value={@organisation.tax_name || ""}
          maxlength="12"
          autocomplete="off"
          hint="For example GST or VAT. Leave it empty to record no tax on an expense."
        />
        <footer><.button type="submit">Save the name</.button></footer>
      </form>
    </section>
    """
  end

  @doc "The currency of an organisation, and the form that changes it."
  attr :organisation, :any, required: true
  attr :can_change?, :any, required: true
  attr :currencies, :list, required: true

  def currency_setting(assigns) do
    ~H"""
    <section aria-labelledby="currency-heading">
      <h2 id="currency-heading"><.icon name="banknotes" /> Currency</h2>
      <p>
        The currency of the amounts is <strong>{ExpenseWords.currency_name(@organisation.currency)} ({@organisation.currency})</strong>. An amount looks like this: <span data-money>{ExpenseWords.money(Money.new(@organisation.currency, "1234.5"))}</span>.
      </p>
      <form :if={@can_change?} id="currency" phx-submit="save_currency">
        <.input
          id="currency-code"
          name="currency[code]"
          type="select"
          label="Currency of a new expense"
          value={@organisation.currency}
          options={for {code, name} <- @currencies, do: {"#{name} (#{code})", code}}
          hint="An expense keeps the currency that it was recorded in. Rescord converts no amount."
        />
        <footer><.button type="submit">Save the currency</.button></footer>
      </form>
    </section>
    """
  end
end
