defmodule RescordWeb.JournalComponents do
  @moduledoc """
  The parts of the journal of a resident (ADR 0030 and ADR 0037): the form
  of a new entry, an entry, and the forms that correct an entry, plan a dose
  and add to an entry.
  """

  use RescordWeb, :html

  alias Rescord.{Accounts, Journal}
  alias RescordWeb.{JournalWords, UploadWords}

  @doc "The form of a new journal entry, with the fields of the kind that the member chooses."
  attr :form, :any, required: true
  attr :kind, :any, required: true
  attr :lists, :any, required: true
  attr :units, :list, required: true, doc: "the units of the chosen measure kind"

  attr :unit_needed?, :boolean,
    default: false,
    doc: "the chosen measure kind has a standard unit, so a measurement needs a unit"

  attr :prescriptions, :any, required: true
  attr :uploads, :any, required: true
  attr :conditions, :list, default: [], doc: "the conditions of the resident, as options"
  attr :joins, :any, default: nil, doc: "the ongoing condition that a diagnosis joins, or nil"
  attr :resident, :any, default: nil
  attr :open?, :boolean, default: false

  def new_entry(assigns) do
    ~H"""
    <details id="new-entry" open={@open?}>
      <summary><.icon name="plus" /> New journal entry</summary>
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
        <p :if={@kind == :diagnosis and @joins} id="entry-joins">
          {name(@resident)} has {@joins.condition.label} since {RescordWeb.ResidentWords.date(
            @joins.started_on
          )}. This entry joins it.
        </p>
        <.input
          :if={@kind == :diagnosis and is_nil(@joins)}
          field={@form[:onset_on]}
          type="date"
          label="First day, if not the day of the entry"
        />
        <.input
          :if={@kind == :diagnosis and is_nil(@joins)}
          field={@form[:chronic]}
          type="checkbox"
          label={"Chronic: #{name(@resident)} keeps this condition"}
        />
        <.input
          :if={@kind != :diagnosis and @conditions != []}
          field={@form[:episode_id]}
          type="select"
          label="About the condition"
          prompt="No condition"
          options={@conditions}
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
          type="decimal"
          label="Value"
          required
        />
        <.input
          :if={@kind == :measurement}
          field={@form[:unit_id]}
          type="select"
          label="Unit"
          prompt={if @unit_needed?, do: nil, else: "No unit"}
          options={@units}
          required={@unit_needed?}
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

  # A correction changes the value as it was recorded, in the unit that
  # the person chose then, and not in the standard unit of the kind.
  defp value_label(%{unit: %{label: label}}), do: "Value, in #{label}"
  defp value_label(_measurement), do: "Value"

  @doc "The form that corrects an entry, for its author and an administrator."
  attr :entry, :any, required: true
  attr :conditions, :list, default: [], doc: "the conditions of the resident, as options"

  def correct_form(assigns) do
    ~H"""
    <details id={"correct-details-#{@entry.id}"}>
      <summary><.icon name="pencil" /> Correct this entry</summary>
      <p>Correct a mistake only. The history keeps the entry as it was.</p>
      <form id={"correct-#{@entry.id}"} phx-submit="correct">
        <input type="hidden" name="entry_id" value={@entry.id} />
        <.input
          :if={@entry.measurement}
          id={"correct-#{@entry.id}-value"}
          name="entry[value]"
          type="decimal"
          label={value_label(@entry.measurement)}
          value={@entry.measurement.value |> Decimal.normalize() |> Decimal.to_string(:normal)}
        />
        <.input
          :if={about?(@entry) and @conditions != []}
          id={"correct-#{@entry.id}-episode"}
          name="entry[episode_id]"
          type="select"
          label="About the condition"
          prompt="No condition"
          options={@conditions}
          value={@entry.episode_id}
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
      <summary><.icon name="pill" /> Plan a dose</summary>
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
          <span :for={error <- upload_errors(@upload, entry)} role="alert">{UploadWords.of(
            error,
            entry,
            &upload_words/1
          )}</span>
          <.button
            type="button"
            phx-click="cancel_file"
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
          <a href={attachment_url(@organisation, attachment)}>
            {attachment.name}
          </a>
          <small>{JournalWords.file_size(attachment.size)}</small>
          <.button
            :if={Journal.can_remove_attachment?(@role, @current_user, attachment)}
            phx-click="remove_attachment"
            phx-value-id={attachment.id}
            aria-label={"Take off #{attachment.name}"}
          >
            <.icon name="x-mark" /> Take off
          </.button>
        </li>
      </ul>
    </section>
    """
  end

  @doc """
  The link that opens a file of an entry: the display file of a photo
  (issue 34), or the file itself for a PDF, a GIF and a photo with no
  display file yet.
  """
  def attachment_url(organisation, attachment) do
    if attachment.display_key,
      do: ~p"/o/#{organisation.short_name}/attachments/#{attachment.id}/display",
      else: ~p"/o/#{organisation.short_name}/attachments/#{attachment.id}"
  end

  @doc "The form that adds to an entry."

  attr :entry, :any, required: true

  def addendum_form(assigns) do
    ~H"""
    <details id={"add-details-#{@entry.id}"}>
      <summary><.icon name="arrow-turn-down-right" /> Add to this entry</summary>
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
  attr :conditions, :list, default: [], doc: "the conditions of the resident, as options"
  attr :can_track?, :boolean, default: false

  attr :comments_link?, :boolean,
    default: true,
    doc: "a link to the entry alone, with its comments (ADR 0106)"

  def entry_card(assigns) do
    ~H"""
    <article id={"entry-#{@entry.id}"}>
      <header>
        <strong><.icon name={Icons.entry_kind(@entry.kind)} /> {JournalWords.kind(@entry.kind)}</strong>
        <small>
          <time datetime={DateTime.to_iso8601(@entry.happened_at)}>
            {when_words(@organisation, @entry.happened_at)}
          </time>
          · {author(@authors, @entry, @current_user)}
        </small>
      </header>
      <p :if={@entry.follows}>
        <.icon name="arrow-turn-down-right" />
        Adds to the entry of {when_words(@organisation, @entry.follows.happened_at)}.
      </p>
      <p :if={@entry.episode} data-about>
        About
        <.link patch={
          RescordWeb.ConditionComponents.journal_path(@organisation, @entry.resident_id,
            episode: @entry.episode_id
          )
        }>{@entry.episode.condition.label}</.link>
      </p>
      <p :if={JournalWords.facts(@entry)}>{JournalWords.facts(@entry)}</p>
      <p :if={@entry.note}>{@entry.note}</p>
      <p :if={@comments_link?}>
        <.link patch={
          RescordWeb.ConditionComponents.journal_path(@organisation, @entry.resident_id,
            entry: @entry.id
          )
        }>Comments</.link>
      </p>

      <.entry_files
        attachments={@attachments}
        entry={@entry}
        organisation={@organisation}
        role={@role}
        current_user={@current_user}
      />

      <.correct_form
        :if={Journal.can_correct?(@role, @current_user, @entry)}
        entry={@entry}
        conditions={@conditions}
      />

      <details :if={@can_track? and untracked?(@entry)} id={"track-details-#{@entry.id}"}>
        <summary><.icon name="pulse" /> Track this condition</summary>
        <p>
          This diagnosis is from before Rescord recorded the conditions of a resident. Track it to
          start the condition on the day of this entry. Then mark the condition as resolved when
          it is over.
        </p>
        <.button phx-click="track" phx-value-entry_id={@entry.id}>Track this condition</.button>
      </details>

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

  # An entry that a correction can give a condition: a diagnosis has the
  # condition that it names, and an addendum the one of its entry.
  defp about?(entry), do: entry.kind != :diagnosis and is_nil(entry.follows_id)

  # A diagnosis with no condition of the resident: one from before Rescord
  # recorded them (ADR 0083), or one whose condition a person removed.
  defp untracked?(entry),
    do: entry.kind == :diagnosis and is_nil(entry.follows_id) and is_nil(entry.episode)

  defp name(%{name: name}) when is_binary(name), do: name
  defp name(_resident), do: "The resident"

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
