defmodule RescordWeb.ResidentComponents do
  @moduledoc """
  The parts of the page of a resident (ADR 0037): its facts, its stay,
  its journal, its family and groups, its identifiers, its history, and
  its removal.
  """

  use RescordWeb, :html

  alias Rescord.Residents
  alias RescordWeb.ResidentWords

  @doc """
  The facts of a resident. The markings are free text that a resident can
  be without, so their row is there only when the resident has them.
  """
  attr :resident, :any, required: true
  attr :today, :any, required: true

  def about(assigns) do
    ~H"""
    <section aria-labelledby="about-heading">
      <h2 id="about-heading">About</h2>
      <.list>
        <:item title="Species">{@resident.species.label}</:item>
        <:item title="Sex">{ResidentWords.sex(@resident.sex)}</:item>
        <:item title="Desex status">{ResidentWords.desex(@resident.desex_status)}</:item>
        <:item title="Born">{born(@resident, @today)}</:item>
        <:item title="Breed">{labels(@resident.resident_breeds, :breed)}</:item>
        <:item title="Colour">{labels(@resident.resident_colours, :colour)}</:item>
        <:item title="Size class">{label(@resident.size_class)}</:item>
        <:item title="Coat">{label(@resident.coat)}</:item>
        <:item :if={@resident.markings} title="Markings">{@resident.markings}</:item>
        <:item title="Temperament">
          {labels(@resident.resident_temperaments, :temperament)}
        </:item>
      </.list>
    </section>
    """
  end

  @doc "The form of the arrival of a resident that is expected."
  attr :arrival_form, :any, required: true

  def arrival_form(assigns) do
    ~H"""
    <details
      id="arrival-details"
      open
    >
      <summary><.icon name="door-in" /> Record the arrival</summary>
      <.form for={@arrival_form} id="arrival" phx-submit="record_arrival">
        <.input
          field={@arrival_form[:kind]}
          type="select"
          label="How the resident came"
          prompt="Choose"
          options={ResidentWords.options(:arrival)}
          required
        />
        <.input field={@arrival_form[:arrived_on]} type="date" label="Date" required />
        <.input field={@arrival_form[:note]} type="text" label="Note" />
        <footer><.button type="submit">Record the arrival</.button></footer>
      </.form>
    </details>
    """
  end

  @doc "The form that marks a resident as away for a time."
  attr :absence_form, :any, required: true

  def absence_form(assigns) do
    ~H"""
    <details id="absence-details">
      <summary><.icon name="map-pin" /> Mark as away for a time</summary>
      <.form for={@absence_form} id="absence" phx-submit="start_absence">
        <.input field={@absence_form[:reason]} type="text" label="Where and why" required />
        <.input
          field={@absence_form[:expected_back_on]}
          type="date"
          label="Expected back"
          hint="After this day, the first page shows the resident as late back."
        />
        <.input
          field={@absence_form[:at]}
          type="datetime-local"
          label="When it went away, if not now"
        />
        <footer><.button type="submit">Mark as away</.button></footer>
      </.form>
    </details>
    """
  end

  @doc "The form of the departure of a resident."
  attr :departure_form, :any, required: true

  def departure_form(assigns) do
    ~H"""
    <details id="departure-details">
      <summary><.icon name="door-out" /> Record the departure</summary>
      <.form for={@departure_form} id="departure" phx-submit="record_departure">
        <.input
          field={@departure_form[:kind]}
          type="select"
          label="How the resident left"
          prompt="Choose"
          options={ResidentWords.options(:departure)}
          required
        />
        <.input field={@departure_form[:departed_on]} type="date" label="Date" required />
        <.input field={@departure_form[:note]} type="text" label="How and why" />
        <footer><.button type="submit">Record the departure</.button></footer>
      </.form>
    </details>
    """
  end

  @doc "Where a resident lives, and its arrival, absence and departure."
  attr :homes, :any, required: true
  attr :organisation, :any, required: true
  attr :resident, :any, required: true
  attr :role, :any, required: true
  attr :arrival_form, :any, required: true
  attr :absence_form, :any, required: true
  attr :departure_form, :any, required: true
  attr :problems, :list, default: []
  attr :problems_at, :any, default: nil

  def stay(assigns) do
    ~H"""
    <section aria-labelledby="stay-heading">
      <h2 id="stay-heading"><.icon name="kennel" /> Stay</h2>
      <.problems list={@problems} at={@problems_at} here={:stay} />

      <h3>Where it lives</h3>
      <p :if={@homes == []}>
        The resident has no place in the housing. A member gives it one on <.link navigate={
          ~p"/o/#{@organisation.short_name}/housing"
        }>the housing page</.link>.
      </p>
      <ul :if={@homes != []}>
        <li :for={home <- @homes}>
          <.link navigate={location_path(@organisation, home.location.id)}>{home.location.name}</.link>
          <span :if={home.with == :own}>(a placement of its own)</span>
          <span :if={home.with != :own}>(with {Residents.group_name(home.with)})</span>
        </li>
      </ul>

      <.list :if={@resident.arrival}>
        <:item title="Arrival">
          {ResidentWords.arrival(@resident.arrival.kind)}, {ResidentWords.date(
            @resident.arrival.arrived_on
          )}
        </:item>
        <:item :if={@resident.arrival.note} title="Note about the arrival">
          {@resident.arrival.note}
        </:item>
      </.list>

      <.arrival_form
        :if={is_nil(@resident.arrival) and can?(@role, :arrival, :record)}
        arrival_form={@arrival_form}
      />

      <div :if={@resident.absence}>
        <.list>
          <:item title="Away">{@resident.absence.reason}</:item>
          <:item :if={@resident.absence.expected_back_on} title="Expected back">
            {ResidentWords.date(@resident.absence.expected_back_on)}
          </:item>
        </.list>
        <form :if={can?(@role, :absence, :finish)} id="back" phx-submit="finish_absence">
          <.input
            id="back-at"
            name="back[at]"
            type="datetime-local"
            label="When it came back, if not now"
            value=""
          />
          <.button type="submit"><.icon name="door-in" /> Mark as back</.button>
        </form>
      </div>

      <.absence_form
        :if={@resident.status == :in_care and can?(@role, :absence, :start)}
        absence_form={@absence_form}
      />

      <div :if={@resident.departure}>
        <.list>
          <:item title="Departure">
            {ResidentWords.departure(@resident.departure.kind)}, {ResidentWords.date(
              @resident.departure.departed_on
            )}
          </:item>
          <:item :if={@resident.departure.note} title="Note about the departure">
            {@resident.departure.note}
          </:item>
        </.list>
        <.confirm
          :if={can?(@role, :departure, :withdraw)}
          id="withdraw-departure"
          summary="Withdraw the departure"
          icon="arrow-uturn-left"
        >
          <p>The resident is in care again, as if it never left.</p>
          <.button variant="danger" phx-click="withdraw_departure">Withdraw the departure</.button>
        </.confirm>
      </div>

      <.departure_form
        :if={@resident.arrival && is_nil(@resident.departure) && can?(@role, :departure, :record)}
        departure_form={@departure_form}
      />
    </section>
    """
  end

  @doc """
  The newest measurement of each kind of a resident, and the links to its
  measurements over time, its journal and its timeline. `measurements` is
  the series of `Rescord.Journal.series/2`.
  """
  attr :measurements, :list, required: true
  attr :organisation, :any, required: true
  attr :resident, :any, required: true

  def journal_summary(assigns) do
    ~H"""
    <section aria-labelledby="journal-heading">
      <h2 id="journal-heading">Journal</h2>
      <p :if={@measurements == []}>
        No weight or other measurement yet. Record one on the page of the measurements.
      </p>
      <RescordWeb.MeasurementComponents.newest_values
        :if={@measurements != []}
        series={@measurements}
        organisation={@organisation}
      />
      <p>
        <.link
          navigate={~p"/o/#{@organisation.short_name}/residents/#{@resident.id}/measurements"}
          data-variant="secondary"
        >
          <.icon name="chart-line" /> Measurements
        </.link>
        <.link
          navigate={~p"/o/#{@organisation.short_name}/residents/#{@resident.id}/journal"}
          data-variant="secondary"
        >
          <.icon name="book-open" /> Open the journal
        </.link>
        <.link
          navigate={~p"/o/#{@organisation.short_name}/residents/#{@resident.id}/timeline"}
          data-variant="secondary"
        >
          <.icon name="timeline" /> Open the timeline
        </.link>
        <%!-- The dose calculator of the tools, with the weight of this resident (ADR 0072). --%>
        <.link
          :if={@resident.status != :left}
          navigate={~p"/o/#{@organisation.short_name}/tools/dose?#{[resident: @resident.id]}"}
          data-variant="secondary"
        >
          <.icon name="calculator" /> Calculate a dose
        </.link>
      </p>
    </section>
    """
  end

  @doc "The form that records a parent of a resident."
  attr :parent_form, :any, required: true
  attr :other_residents, :any, required: true

  def parent_form(assigns) do
    ~H"""
    <details id="parent-details">
      <summary><.icon name="plus" /> Add a parent</summary>
      <.form for={@parent_form} id="parent" phx-submit="record_parent">
        <.input
          field={@parent_form[:parent_id]}
          type="select"
          label="Parent"
          prompt="Choose"
          options={@other_residents}
          required
        />
        <.input
          field={@parent_form[:role]}
          type="select"
          label="Mother or father"
          options={ResidentWords.options(:kin)}
        />
        <footer><.button type="submit">Add the parent</.button></footer>
      </.form>
    </details>
    """
  end

  @doc "The form that puts a resident in a family."
  attr :family_form, :any, required: true
  attr :other_families, :any, required: true

  def family_form(assigns) do
    ~H"""
    <details id="family-details">
      <summary><.icon name="plus" /> Add to a family</summary>
      <.form for={@family_form} id="family" phx-submit="add_to_family">
        <.input
          :if={@other_families != []}
          field={@family_form[:family_id]}
          type="select"
          label="A family that is there"
          prompt="Choose"
          options={@other_families}
        />
        <.input
          field={@family_form[:name]}
          type="text"
          label="Or the name of a new family"
          maxlength="80"
        />
        <footer><.button type="submit">Add to the family</.button></footer>
      </.form>
    </details>
    """
  end

  @doc "The parents, the young, the families and the groups of a resident."
  attr :relations, :any, required: true
  attr :organisation, :any, required: true
  attr :role, :any, required: true
  attr :other_residents, :any, required: true
  attr :parent_form, :any, required: true
  attr :family_form, :any, required: true
  attr :other_families, :any, required: true
  attr :problems, :list, default: []
  attr :problems_at, :any, default: nil

  def relations(assigns) do
    ~H"""
    <section aria-labelledby="relations-heading">
      <h2 id="relations-heading"><.icon name="paws" /> Family and groups</h2>
      <.problems list={@problems} at={@problems_at} here={:relations} />

      <h3>Parents</h3>
      <p :if={@relations.parents == []}>No parent is recorded.</p>
      <ul :if={@relations.parents != []}>
        <li :for={link <- @relations.parents}>
          {ResidentWords.kin(link.role)}:
          <.link navigate={resident_path(@organisation, link.parent_id)}>{name(link.parent)}</.link>
          <.confirm
            :if={can?(@role, :parent, :remove)}
            id={"remove-parent-#{link.id}"}
            summary="Remove"
            label={"Remove the #{String.downcase(ResidentWords.kin(link.role))} #{name(link.parent)}"}
          >
            <p>The tie to this parent goes. Both residents stay.</p>
            <.button variant="danger" phx-click="remove_parent" phx-value-id={link.id}>
              Remove the {String.downcase(ResidentWords.kin(link.role))} {name(link.parent)}
            </.button>
          </.confirm>
        </li>
      </ul>

      <.parent_form
        :if={can?(@role, :parent, :record) and @other_residents != []}
        parent_form={@parent_form}
        other_residents={@other_residents}
      />

      <div :if={@relations.young != []}>
        <h3>Young</h3>
        <ul>
          <li :for={link <- @relations.young}>
            <.link navigate={~p"/o/#{@organisation.short_name}/residents/#{link.resident_id}"}>
              {link.resident.name || "A resident with no name"}
            </.link>
          </li>
        </ul>
      </div>

      <h3>Families</h3>
      <p :if={@relations.families == []}>The resident is in no family.</p>
      <ul :if={@relations.families != []}>
        <li :for={membership <- @relations.families}>
          {membership.family.name}
          <.confirm
            :if={can?(@role, :family_member, :remove)}
            id={"take-out-#{membership.id}"}
            summary="Take out"
            label={"Take out of #{membership.family.name}"}
            icon="user-minus"
          >
            <p>The resident leaves the family. The family stays.</p>
            <.button variant="danger" phx-click="remove_from_family" phx-value-id={membership.id}>
              Take out of {membership.family.name}
            </.button>
          </.confirm>
        </li>
      </ul>

      <.family_form
        :if={can?(@role, :family_member, :add)}
        family_form={@family_form}
        other_families={@other_families}
      />

      <h3>Groups</h3>
      <p :if={@relations.groups == []}>
        The resident is in no group. A member adds it on <.link navigate={
          ~p"/o/#{@organisation.short_name}/groups"
        }>the groups page</.link>.
      </p>
      <ul :if={@relations.groups != []}>
        <li :for={{_membership, group} <- @relations.groups}>
          <.link navigate={group_path(@organisation, group.id)}>{Residents.group_name(group)}</.link>
          <span :if={Residents.words(group)}>({Residents.words(group)})</span>
        </li>
      </ul>
    </section>
    """
  end

  @doc "The form that adds an identifier to a resident."
  attr :identifier_form, :any, required: true
  attr :identifier_kinds, :any, required: true

  def identifier_form(assigns) do
    ~H"""
    <details id="identifier-details">
      <summary><.icon name="identification" /> Add an identifier</summary>
      <.form for={@identifier_form} id="identifier" phx-submit="add_identifier">
        <.input
          field={@identifier_form[:kind_id]}
          type="select"
          label="Kind"
          prompt="Choose"
          options={@identifier_kinds}
          required
        />
        <.input field={@identifier_form[:value]} type="text" label="Number or mark" required />
        <footer><.button type="submit">Add the identifier</.button></footer>
      </.form>
    </details>
    """
  end

  @doc """
  The identifiers of a resident. A resident needs none: many species carry
  no microchip and no tag. So the section is there only when the resident
  has an identifier or the person can add one, and it has no sentence about
  an identifier that is not there.
  """
  attr :resident, :any, required: true
  attr :role, :any, required: true
  attr :identifier_kinds, :any, required: true
  attr :identifier_form, :any, required: true
  attr :problems, :list, default: []
  attr :problems_at, :any, default: nil

  def identifiers(assigns) do
    assigns =
      assign(
        assigns,
        :can_add,
        can?(assigns.role, :identifier, :add) and assigns.identifier_kinds != []
      )

    ~H"""
    <section :if={@resident.identifiers != [] or @can_add} aria-labelledby="identifiers-heading">
      <h2 id="identifiers-heading"><.icon name="identification" /> Identifiers</h2>
      <.problems list={@problems} at={@problems_at} here={:identifiers} />
      <ul :if={@resident.identifiers != []}>
        <li :for={identifier <- @resident.identifiers}>
          {identifier.kind.label}: {identifier.value}
          <.confirm
            :if={can?(@role, :identifier, :remove)}
            id={"remove-identifier-#{identifier.id}"}
            summary="Remove"
            label={"Remove the #{identifier.kind.label} #{identifier.value}"}
          >
            <p>The identifier leaves the record of the resident.</p>
            <.button variant="danger" phx-click="remove_identifier" phx-value-id={identifier.id}>
              Remove the {identifier.kind.label} {identifier.value}
            </.button>
          </.confirm>
        </li>
      </ul>

      <.identifier_form
        :if={@can_add}
        identifier_form={@identifier_form}
        identifier_kinds={@identifier_kinds}
      />
    </section>
    """
  end

  @doc "The names and the desex statuses that a resident had."
  attr :names, :any, required: true
  attr :organisation, :any, required: true
  attr :desex_statuses, :any, required: true

  def facts_history(assigns) do
    ~H"""
    <section aria-labelledby="history-heading">
      <h2 id="history-heading">History</h2>

      <div :if={length(@names) > 1}>
        <h3>Names</h3>
        <ol>
          <li :for={name <- @names}>
            {name.value}, from
            <time datetime={DateTime.to_iso8601(name.from)}>{ResidentWords.date(
              Rescord.Accounts.local_date(@organisation, name.from)
            )}</time>
          </li>
        </ol>
      </div>

      <div :if={length(@desex_statuses) > 1}>
        <h3>Desex status</h3>
        <ol>
          <li :for={status <- @desex_statuses}>
            {ResidentWords.desex(status.value)}, from
            <time datetime={DateTime.to_iso8601(status.from)}>{ResidentWords.date(
              Rescord.Accounts.local_date(@organisation, status.from)
            )}</time>
          </li>
        </ol>
      </div>
    </section>
    """
  end

  @doc "The removal of a resident that was recorded by mistake."
  attr :problems, :list, default: []
  attr :problems_at, :any, default: nil

  def removal(assigns) do
    ~H"""
    <section aria-labelledby="remove-heading">
      <h2 id="remove-heading">Remove</h2>
      <.problems list={@problems} at={@problems_at} here={:removal} />
      <.confirm id="remove-details" summary="Remove this resident">
        <p>
          Remove a resident only when somebody recorded it by mistake. For a resident that left,
          record the departure.
        </p>
        <.button variant="danger" phx-click="remove_resident">Remove the resident</.button>
      </.confirm>
    </section>
    """
  end

  def label(nil), do: "Not recorded"

  def label(value), do: value.label

  def labels([], _value), do: "Not recorded"

  def labels(ties, value) do
    ties |> Enum.map(&to_string(Map.fetch!(&1, value).label)) |> Enum.sort() |> Enum.join(", ")
  end

  def born(%{born_on: nil}, _today), do: "Not recorded"

  def born(resident, today) do
    date = ResidentWords.date(resident.born_on)
    date = if resident.born_on_estimated, do: "About #{date}", else: date

    case ResidentWords.age(resident.born_on, today) do
      nil -> date
      age -> "#{date} (#{age} old)"
    end
  end

  def can?(role, subject, action), do: Residents.role_can?(role, subject, action)

  # Short names for the paths, so that a link and its text are on one line:
  # a line break inside a link is a space that the browser underlines.
  def resident_path(organisation, id), do: ~p"/o/#{organisation.short_name}/residents/#{id}"

  def group_path(organisation, id), do: ~p"/o/#{organisation.short_name}/groups/#{id}"

  def location_path(organisation, id), do: ~p"/o/#{organisation.short_name}/housing/#{id}"

  def name(resident), do: resident.name || "A resident with no name"

  @doc "The fields of the facts of a resident that have one value each."
  attr :form, :any, required: true
  attr :lists, :any, required: true

  def resident_fields(assigns) do
    ~H"""
    <fieldset>
      <legend>The resident</legend>
      <.input field={@form[:name]} type="text" label="Name" maxlength="80" />
      <.input
        field={@form[:species_id]}
        type="select"
        label="Species"
        prompt="Choose"
        options={@lists.species}
        required
      />
      <.input field={@form[:sex]} type="select" label="Sex" options={ResidentWords.options(:sex)} />
      <.input
        field={@form[:desex_status]}
        type="select"
        label="Desex status"
        options={ResidentWords.options(:desex)}
        hint="Entire: not spayed or neutered."
      />
      <.input
        field={@form[:born_on]}
        type="date"
        label="Date of birth"
        hint="Not sure of the day? Give a near date, and tick the box below."
      />
      <.input
        field={@form[:born_on_estimated]}
        type="checkbox"
        label="The date of birth is an estimate"
      />
      <.input
        field={@form[:size_class_id]}
        type="select"
        label="Size class"
        prompt="Not recorded"
        options={@lists.size_class}
      />
      <.input
        field={@form[:coat_id]}
        type="select"
        label="Coat"
        prompt="Not recorded"
        options={@lists.coat}
      />
      <.input
        field={@form[:markings]}
        type="textarea"
        label="Markings"
        hint="What tells this resident apart and is in no list, such as a torn ear."
        maxlength="300"
        rows="2"
      />
    </fieldset>
    """
  end

  @doc "The fields of the arrival of a new resident."
  attr :form, :any, required: true

  def arrival_fields(assigns) do
    ~H"""
    <fieldset>
      <legend>The arrival</legend>
      <p>Leave these empty for a resident that is not here yet. It shows as Expected.</p>
      <.input
        field={@form[:arrival_kind]}
        type="select"
        label="How the resident came"
        prompt="Not here yet"
        options={ResidentWords.options(:arrival)}
      />
      <.input field={@form[:arrived_on]} type="date" label="Date of the arrival" />
      <.input field={@form[:arrival_note]} type="text" label="Note about the arrival" />
    </fieldset>
    """
  end
end
