defmodule RescordWeb.AccountComponents do
  @moduledoc """
  The parts of the pages of the accounts (ADR 0021, ADR 0026 and ADR 0037):
  the members of an organisation, the invitation, the organisations and
  the root users of the root page, and the settings of an organisation.
  """

  use RescordWeb, :html

  alias Rescord.Accounts
  alias RescordWeb.{ResidentWords, TaskWords}

  @doc "The members of an organisation, with the actions that the role of the reader can run."
  attr :current_user, :any, required: true
  attr :organisation, :any, required: true
  attr :role, :any, required: true

  def members_table(assigns) do
    ~H"""
    <Cinder.collection
      id="members"
      query={Accounts.query_to_members(%{}, actor: @current_user, tenant: @organisation)}
      actor={@current_user}
      tenant={@organisation}
    >
      <:col :let={member} field="email" label="Email address">{member.email}</:col>
      <:col :let={member} field="role" label="Role" filter sort>{role_word(member.role)}</:col>
      <:col :let={member} field="id" label="Actions">
        <.button
          :if={member.role == :member and Accounts.role_can?(@role, :make_administrator, member)}
          phx-click="make_administrator"
          phx-value-id={member.id}
          aria-label={"Make #{member.email} an administrator"}
        >
          Make administrator
        </.button>
        <.button
          :if={Accounts.role_can?(@role, :remove, member)}
          phx-click="remove"
          phx-value-id={member.id}
          aria-label={"Remove #{member.email} from #{@organisation.name}"}
        >
          Remove
        </.button>
      </:col>
    </Cinder.collection>
    """
  end

  @doc "The form that invites a person to an organisation."
  attr :invite_form, :any, required: true
  attr :can_invite_administrator?, :any, required: true

  def invite_form(assigns) do
    ~H"""
    <section aria-labelledby="invite-heading">
      <h2 id="invite-heading">Invite a person</h2>
      <.form for={@invite_form} id="invite" phx-submit="invite">
        <.input field={@invite_form[:email]} type="email" label="Email address" required />
        <.input
          :if={@can_invite_administrator?}
          field={@invite_form[:role]}
          type="select"
          label="Role"
          options={[{"Member", "member"}, {"Administrator", "administrator"}]}
        />
        <footer>
          <.button type="submit">Send the invitation</.button>
        </footer>
      </.form>
    </section>
    """
  end

  def role_word(:administrator), do: "Administrator"

  def role_word(:member), do: "Member"
  @doc "The organisations, and the form of a new organisation."
  attr :current_user, :any, required: true
  attr :organisation_form, :any, required: true
  attr :time_zones, :any, required: true

  def organisations(assigns) do
    ~H"""
    <section aria-labelledby="organisations-heading">
      <h2 id="organisations-heading">Organisations</h2>

      <Cinder.collection
        id="organisations"
        query={Accounts.query_to_organisations(%{}, actor: @current_user)}
        actor={@current_user}
      >
        <:col :let={organisation} field="name" label="Name" filter sort>
          <a href={~p"/o/#{organisation.short_name}/members"}>{organisation.name}</a>
        </:col>
        <:col :let={organisation} field="time_zone" label="Time zone" sort>
          {organisation.time_zone}
        </:col>
        <:col :let={organisation} field="short_name" label="Short name" sort>
          {organisation.short_name}
        </:col>
      </Cinder.collection>

      <.form for={@organisation_form} id="new-organisation" phx-submit="create_organisation">
        <h3>New organisation</h3>
        <.input field={@organisation_form[:name]} label="Name" required />
        <.input
          field={@organisation_form[:short_name]}
          label="Short name, for the address of its pages"
          required
        />
        <.input
          field={@organisation_form[:time_zone]}
          label="Time zone, for example Australia/Brisbane"
          list="time-zones"
          autocomplete="off"
          required
        />
        <datalist id="time-zones">
          <option :for={zone <- @time_zones} value={zone}></option>
        </datalist>
        <footer>
          <.button type="submit">Create the organisation</.button>
        </footer>
      </.form>
    </section>
    """
  end

  @doc "The root users, and the form that makes a user a root user."
  attr :roots, :any, required: true
  attr :current_user, :any, required: true
  attr :root_form, :any, required: true

  def root_users(assigns) do
    ~H"""
    <section aria-labelledby="roots-heading">
      <h2 id="roots-heading">Root users</h2>

      <ul>
        <li :for={root <- @roots}>
          {root.email}
          <.button
            :if={root.id != @current_user.id}
            phx-click="revoke_root"
            phx-value-id={root.id}
            aria-label={"Make #{root.email} an ordinary user"}
          >
            Make an ordinary user
          </.button>
        </li>
      </ul>

      <.form for={@root_form} id="new-root" phx-submit="make_root">
        <h3>Make a user a root user</h3>
        <.input field={@root_form[:email]} type="email" label="Email address of the user" required />
        <footer>
          <.button type="submit">Make a root user</.button>
        </footer>
      </.form>
    </section>
    """
  end

  @doc "The time zone of an organisation, and the form that changes it."
  attr :organisation, :any, required: true
  attr :today, :any, required: true
  attr :can_change?, :any, required: true
  attr :form, :any, required: true
  attr :time_zones, :any, required: true

  def time_zone_setting(assigns) do
    ~H"""
    <section aria-labelledby="time-zone-heading">
      <h2 id="time-zone-heading">Time zone</h2>
      <.list>
        <:item title="Time zone">{@organisation.time_zone}</:item>
        <:item title="Today here">{ResidentWords.date(@today)}</:item>
      </.list>
      <p>
        The time zone says what today is for {@organisation.name}: a date of an arrival or a
        departure is not after today, and the age of a resident counts to today.
      </p>

      <.form :if={@can_change?} for={@form} id="settings" phx-submit="save">
        <.input
          field={@form[:time_zone]}
          label="Time zone, for example Australia/Brisbane"
          list="time-zones"
          autocomplete="off"
          required
        />
        <datalist id="time-zones">
          <option :for={zone <- @time_zones} value={zone}></option>
        </datalist>
        <footer><.button type="submit">Save the time zone</.button></footer>
      </.form>
    </section>
    """
  end

  @doc "How many days ahead the tasks of the routines exist, and the form that changes it."
  attr :organisation, :any, required: true
  attr :can_change?, :any, required: true
  attr :ahead_form, :any, required: true

  def days_ahead_setting(assigns) do
    ~H"""
    <section aria-labelledby="ahead-heading">
      <h2 id="ahead-heading">Tasks of the routines</h2>
      <.list>
        <:item title="The tasks exist">{TaskWords.days(@organisation.task_days_ahead)} ahead</:item>
      </.list>
      <p>
        Rescord makes the tasks of each routine this number of days ahead. A routine can have
        a number of its own. A smaller number here removes no task that exists.
      </p>

      <.form :if={@can_change?} for={@ahead_form} id="ahead" phx-submit="save_ahead">
        <.input
          field={@ahead_form[:task_days_ahead]}
          type="number"
          label="Days ahead, from 1 to 400"
          min="1"
          max="400"
          required
        />
        <footer><.button type="submit">Save the days ahead</.button></footer>
      </.form>
    </section>
    """
  end
end
