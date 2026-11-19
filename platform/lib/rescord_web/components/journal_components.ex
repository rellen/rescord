defmodule RescordWeb.JournalComponents do
  @moduledoc """
  The parts of the journal of a resident (ADR 0030 and ADR 0037): the form
  of a new entry, an entry, and the forms that correct an entry, plan a dose
  and add to an entry.
  """

  use RescordWeb, :html

  alias Rescord.{Accounts, Journal}
  alias RescordWeb.JournalWords

  @doc "The form of a new journal entry, with the fields of the kind that the member chooses."
  attr :form, :any, required: true
  attr :kind, :any, required: true
  attr :lists, :any, required: true
  attr :units, :list, required: true, doc: "the units of the chosen measure kind"
  attr :prescriptions, :any, required: true
  attr :uploads, :any, required: true

  def new_entry(assigns) do
    ~H"""
    <details id="new-entry">
      <summary>New journal entry</summary>
      <.form for={@form} id="entry" phx-change="choose" phx-submit="write">
        <.input
          field={@form[:kind]}
          type="select"
          label="Kind"
          options={JournalWords.options(:kind)}
        />
        <.input
          :if={@kind == :diagnosis}
          field={@form[:condition_id]}
          type="select"
          label="Condition"
          prompt="Choose"
          options={@lists.condition}
          required
        />
        <.input
          :if={@kind == :measurement}
          field={@form[:measure_kind_id]}
          type="select"
          label="What was measured"
          prompt="Choose"
          options={@lists.measure_kind}
          required
        />
        <.input
          :if={@kind == :measurement}
          field={@form[:value]}
          type="number"
          step="any"
          label="Value"
          required
        />
        <.input
          :if={@kind == :measurement}
          field={@form[:unit_id]}
          type="select"
          label="Unit"
          prompt="No unit"
          options={@units}
        />
        <.input
          :if={@kind == :procedure}
          field={@form[:procedure_kind_id]}
          type="select"
          label="Procedure"
          prompt="Choose"
          options={@lists.procedure_kind}
          required
        />
        <.input
          :if={@kind == :vaccination}
          field={@form[:vaccine]}
          type="text"
          label="Vaccine"
          maxlength="120"
          required
        />
        <.input
          :if={@kind == :prescription}
          field={@form[:medication]}
          type="text"
          label="Medication"
          maxlength="120"
          required
        />
        <.input
          :if={@kind == :prescription}
          field={@form[:dose]}
          type="text"
          label="How much and how often"
          maxlength="200"
        />
        <.input
          :if={@kind == :prescription}
          field={@form[:route]}
          type="select"
          label="Route"
          prompt="Not recorded"
          options={JournalWords.options(:route)}
        />
        <.input
          :if={@kind == :prescription}
          field={@form[:starts_on]}
          type="date"
          label="First day"
        />
        <.input :if={@kind == :prescription} field={@form[:ends_on]} type="date" label="Last day" />
        <.input
          :if={@kind == :dose and @prescriptions != []}
          field={@form[:prescription_id]}
          type="select"
          label="Of the prescription"
          prompt="No prescription"
          options={@prescriptions}
        />
        <.input
          :if={@kind == :dose}
          field={@form[:amount]}
          type="text"
          label="How much"
          maxlength="120"
        />
        <.input
          field={@form[:note]}
          type="textarea"
          label={if Journal.needs(@kind), do: "Note", else: "What happened"}
          maxlength="2000"
          required={is_nil(Journal.needs(@kind))}
        />
        <.input field={@form[:at]} type="datetime-local" label="When it happened, if not now" />
        <.file_field :if={@uploads[:files]} upload={@uploads.files} />
        <footer><.button type="submit">Write the entry</.button></footer>
      </.form>
    </details>
    """
  end

  @doc "The form that corrects an entry, for its author and an administrator."
  attr :entry, :any, required: true

  def correct_form(assigns) do
    ~H"""
    <details id={"correct-details-#{@entry.id}"}>
      <summary>Correct this entry</summary>
      <p>Correct a mistake only. The history keeps the entry as it was.</p>
      <form id={"correct-#{@entry.id}"} phx-submit="correct">
        <input type="hidden" name="entry_id" value={@entry.id} />
        <.input
          :if={@entry.measurement}
          id={"correct-#{@entry.id}-value"}
          name="entry[value]"
          type="number"
          step="any"
          label="Value"
          value={JournalWords.number(@entry.measurement.value) |> String.replace(",", "")}
        />
        <.input
          id={"correct-#{@entry.id}-note"}
          name="entry[note]"
          type="textarea"
          label="Note"
          value={@entry.note}
          maxlength="2000"
        />
        <footer><.button type="submit">Save the correction</.button></footer>
      </form>
    </details>
    """
  end

  @doc "The form that plans a dose of a prescription as a task."
  attr :entry, :any, required: true
  attr :today, :any, required: true
  attr :organisation, :any, required: true
  attr :can_start_routine?, :boolean, default: false

  def dose_form(assigns) do
    ~H"""
    <details id={"dose-details-#{@entry.id}"}>
      <summary>Plan a dose</summary>
      <p>The dose is a task. The member who completes it writes the dose to this journal.</p>
      <form id={"plan-dose-#{@entry.id}"} phx-submit="plan_dose">
        <input type="hidden" name="entry_id" value={@entry.id} />
        <.input
          id={"plan-dose-#{@entry.id}-date"}
          name="dose[date]"
          type="date"
          label="Day"
          value={Date.to_iso8601(@today)}
          required
        />
        <.input
          id={"plan-dose-#{@entry.id}-time"}
          name="dose[time]"
          type="time"
          label="Time"
          value="08:00"
          required
        />
        <footer><.button type="submit">Plan the dose</.button></footer>
      </form>
      <p :if={@can_start_routine?}>
        <.link navigate={
          ~p"/o/#{@organisation.short_name}/routines?prescription=#{@entry.prescription.id}"
        }>Plan the doses as a routine</.link>
      </p>
    </details>
    """
  end

  @doc """
  The files of a new entry: a photo or a PDF, five at most, each with its
  progress, its problems, and a button that takes it out.
  """
  attr :upload, :any, required: true

  def file_field(assigns) do
    ~H"""
    <fieldset id="entry-files">
      <legend>Files: photos or PDFs, five at most, each 20 MB at most</legend>
      <label for={@upload.ref}>Choose files</label>
      <.live_file_input upload={@upload} />
      <p :for={error <- upload_errors(@upload)} role="alert">{upload_words(error)}</p>
      <ul :if={@upload.entries != []}>
        <li :for={entry <- @upload.entries} id={"file-#{entry.ref}"}>
          {entry.client_name}
          <progress value={entry.progress} max="100" aria-label={"Sent of #{entry.client_name}"}>
            {entry.progress} percent
          </progress>
          <span :for={error <- upload_errors(@upload, entry)} role="alert">{upload_words(error)}</span>
          <.button
            type="button"
            phx-click="cancel_file"
            phx-value-ref={entry.ref}
            aria-label={"Take #{entry.client_name} out"}
          >
            Take out
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

  @doc "The files of an entry, each with a link that opens it."
  attr :attachments, :list, required: true
  attr :entry, :any, required: true
  attr :organisation, :any, required: true
  attr :role, :any, required: true
  attr :current_user, :any, required: true

  def entry_files(assigns) do
    ~H"""
    <section :if={@attachments != []} aria-label="Files of the entry">
      <ul>
        <li :for={attachment <- @attachments} id={"attachment-#{attachment.id}"}>
          <a href={~p"/o/#{@organisation.short_name}/attachments/#{attachment.id}"}>
            {attachment.name}
          </a>
          <small>{JournalWords.file_size(attachment.size)}</small>
          <.button
            :if={Journal.can_remove_attachment?(@role, @current_user, attachment)}
            phx-click="remove_attachment"
            phx-value-id={attachment.id}
            aria-label={"Take #{attachment.name} off the entry"}
          >
            Take off
          </.button>
        </li>
      </ul>
    </section>
    """
  end

  @doc "The form that adds to an entry."
  attr :entry, :any, required: true

  def addendum_form(assigns) do
    ~H"""
    <details id={"add-details-#{@entry.id}"}>
      <summary>Add to this entry</summary>
      <form id={"add-#{@entry.id}"} phx-submit="write">
        <input type="hidden" name="entry[kind]" value={@entry.kind} />
        <input type="hidden" name="entry[follows_id]" value={@entry.id} />
        <.input
          id={"add-#{@entry.id}-note"}
          name="entry[note]"
          type="textarea"
          label="What to add"
          value=""
          maxlength="2000"
          required
        />
        <footer><.button type="submit">Add to the entry</.button></footer>
      </form>
    </details>
    """
  end

  @doc "One journal entry, with what a member can do with it."
  attr :entry, :any, required: true
  attr :organisation, :any, required: true
  attr :authors, :any, required: true
  attr :current_user, :any, required: true
  attr :role, :any, required: true
  attr :can_plan?, :any, required: true
  attr :today, :any, required: true
  attr :can_write?, :any, required: true
  attr :can_start_routine?, :boolean, default: false

  attr :attachments, :list, default: []

  def entry_card(assigns) do
    ~H"""
    <article id={"entry-#{@entry.id}"}>
      <header>
        <strong>{JournalWords.kind(@entry.kind)}</strong>
        <small>
          <time datetime={DateTime.to_iso8601(@entry.happened_at)}>
            {when_words(@organisation, @entry.happened_at)}
          </time>
          · {author(@authors, @entry, @current_user)}
        </small>
      </header>
      <p :if={@entry.follows}>
        Adds to the entry of {when_words(@organisation, @entry.follows.happened_at)}.
      </p>
      <p :if={JournalWords.facts(@entry)}>{JournalWords.facts(@entry)}</p>
      <p :if={@entry.note}>{@entry.note}</p>

      <.entry_files
        attachments={@attachments}
        entry={@entry}
        organisation={@organisation}
        role={@role}
        current_user={@current_user}
      />

      <.correct_form :if={Journal.can_correct?(@role, @current_user, @entry)} entry={@entry} />

      <.dose_form
        :if={@entry.prescription && @can_plan?}
        entry={@entry}
        today={@today}
        organisation={@organisation}
        can_start_routine?={@can_start_routine?}
      />

      <.addendum_form :if={@can_write?} entry={@entry} />
    </article>
    """
  end

  # The address of the author, when the author is a member. A root user is
  # not a member, and reads their own entries as their own.
  def author(authors, entry, user) do
    cond do
      Map.has_key?(authors, entry.author_id) -> authors[entry.author_id]
      entry.author_id == user.id -> to_string(user.email)
      true -> "a person who is not a member now"
    end
  end

  def when_words(organisation, instant),
    do: JournalWords.time(Accounts.local_time(organisation, instant))
end
