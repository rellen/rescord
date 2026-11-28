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
  attr :roles, :list, required: true, doc: "the roles that the reader can give, as options"
  attr :all_roles, :list, required: true, doc: "each role of the organisation, as options"
  attr :url_state, :any, required: true, doc: "the state of the table in the address"

  attr :can_erase?, :boolean,
    default: false,
    doc: "whether the person records a request to erase data"

  def members_table(assigns) do
    ~H"""
    <Cinder.collection
      id="members"
      query={Accounts.query_to_members(%{}, actor: @current_user, tenant: @organisation)}
      query_opts={[load: [:role]]}
      actor={@current_user}
      tenant={@organisation}
      url_state={@url_state}
      search={[label: "Search", placeholder: "An email address", fn: &search_members/3]}
    >
      <:empty :let={found}>
        <p :if={found.filtered?}>No member matches the search and the filter.</p>
        <p :if={not found.filtered?}>{@organisation.name} has no member yet.</p>
      </:empty>
      <:col :let={member} field="email" label="Email address" search>{member.email}</:col>
      <:col
        :let={member}
        field="role_id"
        label="Role"
        filter={[type: :select, prompt: "Any role", options: @all_roles]}
      >
        <span data-label="Role">{member.role.name}</span>
      </:col>
      <:col :let={member} field="id" label="Actions">
        <form
          :if={@roles != [] and Accounts.role_can?(@role, :set_role, member, @organisation)}
          id={"role-of-#{member.id}"}
          phx-submit="set_role"
        >
          <input type="hidden" name="member_id" value={member.id} />
          <.input
            id={"role-of-#{member.id}-role"}
            name="member_role[role_id]"
            type="select"
            label={"The role of #{member.email}"}
            options={@roles}
            value={member.role_id}
          />
          <.button type="submit" aria-label={"Give the role to #{member.email}"}><.icon name="key" />
          Give the role</.button>
        </form>
        <.button
          :if={Accounts.role_can?(@role, :remove, member, @organisation)}
          phx-click="remove"
          phx-value-id={member.id}
          data-confirm={"Remove #{member.email} from #{@organisation.name}? Their records stay theirs, marked as a former member. The tasks that are due for them alone become for anybody, and their calendar feeds stop."}
          aria-label={"Remove #{member.email} from #{@organisation.name}"}
        >
          <.icon name="user-minus" /> Remove
        </.button>
        <.link
          :if={@can_erase? and member.user_id != @current_user.id}
          navigate={~p"/o/#{@organisation.short_name}/privacy?member=#{member.id}"}
          aria-label={"Erase on request the data of #{member.email}"}
        >
          Erase on request
        </.link>
      </:col>
    </Cinder.collection>
    """
  end

  # The search of the members table. Cinder cannot search the email address
  # itself, which Elixir calculates, so the domain narrows the query.
  defp search_members(query, _columns, text), do: Accounts.members_with_email(query, text)

  @doc """
  The members who were removed from the organisation and are not members
  again (ADR 0105). Their records stay theirs, marked as a former member.
  """
  attr :former, :list, required: true, doc: "each former member, with `email`"
  attr :organisation, :any, required: true
  attr :can_invite?, :boolean, required: true

  attr :can_erase?, :boolean,
    default: false,
    doc: "whether the person records a request to erase data"

  def former_members(assigns) do
    ~H"""
    <section :if={@former != []} aria-labelledby="former-heading">
      <h2 id="former-heading"><.icon name="user-minus" /> Former members</h2>
      <p>
        These people left {@organisation.name}. What they recorded stays theirs, marked as a former member.
      </p>
      <ul id="former-members">
        <li :for={member <- @former} id={"former-#{member.id}"}>
          <span>{member.email}</span>
          <small>left on {ResidentWords.date(Accounts.local_date(@organisation, member.archived_at))}</small>
          <.button
            :if={@can_invite?}
            phx-click="invite_again"
            phx-value-id={member.id}
            aria-label={"Invite #{member.email} to #{@organisation.name} again"}
          >
            <.icon name="user-plus" /> Invite again
          </.button>
          <.link
            :if={@can_erase?}
            navigate={~p"/o/#{@organisation.short_name}/privacy?member=#{member.id}"}
            aria-label={"Erase on request the data of #{member.email}"}
          >
            Erase on request
          </.link>
        </li>
      </ul>
    </section>
    """
  end

  @doc "The form that invites a person to an organisation, with a role that the person can give."
  attr :invite_form, :any, required: true
  attr :roles, :list, required: true

  def invite_form(assigns) do
    ~H"""
    <section aria-labelledby="invite-heading">
      <h2 id="invite-heading"><.icon name="user-plus" /> Invite a person</h2>
      <.form for={@invite_form} id="invite" phx-submit="invite">
        <.input field={@invite_form[:email]} type="email" label="Email address" required />
        <.input
          :if={@roles != []}
          field={@invite_form[:role_id]}
          type="select"
          label="Role"
          options={@roles}
        />
        <footer>
          <.button type="submit"><.icon name="envelope" /> Send the invitation</.button>
        </footer>
      </.form>
    </section>
    """
  end

  @doc "The organisations, and the form of a new organisation."
  attr :current_user, :any, required: true
  attr :organisation_form, :any, required: true
  attr :time_zones, :any, required: true
  attr :url_state, :any, required: true, doc: "the state of the table in the address"

  def organisations(assigns) do
    ~H"""
    <section aria-labelledby="organisations-heading">
      <h2 id="organisations-heading">Organisations</h2>

      <Cinder.collection
        id="organisations"
        query={Accounts.query_to_organisations(%{}, actor: @current_user)}
        actor={@current_user}
        url_state={@url_state}
      >
        <:empty :let={found}>
          <p :if={found.filtered?}>No organisation matches the filter.</p>
          <p :if={not found.filtered?}>Rescord has no organisation yet.</p>
        </:empty>
        <:col :let={organisation} field="name" label="Name" filter sort>
          <.link navigate={~p"/o/#{organisation.short_name}/members"}>{organisation.name}</.link>
        </:col>
        <:col :let={organisation} field="time_zone" label="Time zone" sort>
          <span data-label="Time zone">{organisation.time_zone}</span>
        </:col>
        <:col :let={organisation} field="short_name" label="Short name" sort>
          <span data-label="Short name">{organisation.short_name}</span>
        </:col>
      </Cinder.collection>

      <.form for={@organisation_form} id="new-organisation" phx-submit="create_organisation">
        <h3>New organisation</h3>
        <.input field={@organisation_form[:name]} label="Name" required />
        <.input
          field={@organisation_form[:short_name]}
          label="Short name, for the address of its pages"
          autocapitalize="none"
          spellcheck="false"
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
        <.input
          field={@organisation_form[:locale]}
          type="select"
          label="Language and region, for the forms of a date, a time and a number"
          options={locale_options()}
          required
        />
        <footer>
          <.button type="submit"><.icon name="plus" /> Create the organisation</.button>
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
            aria-label={"Make an ordinary user of #{root.email}"}
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
      <h2 id="time-zone-heading"><.icon name="globe" /> Time zone</h2>
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

  @doc """
  The language and the region of an organisation (ADR 0075), the forms that
  they give, and the form that changes them. The examples have the forms of
  the locale of the page, which is the one of the organisation.
  """
  attr :organisation, :any, required: true
  attr :can_change?, :any, required: true
  attr :locale_form, :any, required: true

  def locale_setting(assigns) do
    ~H"""
    <section aria-labelledby="locale-heading">
      <h2 id="locale-heading"><.icon name="globe" /> Language and region</h2>
      <.list>
        <:item title="Language and region">{Accounts.locale_name(@organisation.locale)}</:item>
        <:item title="A date">{RescordWeb.Locale.date(~D[2026-11-16])}</:item>
        <:item title="A time of day">{RescordWeb.Locale.time(~T[18:30:00])}</:item>
        <:item title="A number">{RescordWeb.Locale.number(Decimal.new("1234567.5"))}</:item>
      </.list>
      <p>
        The language and region say how the pages of {@organisation.name} write a date, a time
        of day and a number. The words of the pages are English in each one.
      </p>

      <.form :if={@can_change?} for={@locale_form} id="locale" phx-submit="save_locale">
        <.input
          field={@locale_form[:locale]}
          type="select"
          label="Language and region"
          options={locale_options()}
          required
        />
        <footer><.button type="submit">Save the language and region</.button></footer>
      </.form>
    </section>
    """
  end

  # The locales that Rescord offers, as the options of a select.
  defp locale_options, do: for({tag, name} <- Accounts.locales(), do: {name, tag})

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

  @doc "The parts that a copy of a transferred resident holds at first (ADR 0042)."
  attr :organisation, :any, required: true
  attr :can_change?, :boolean, required: true

  def transfer_parts_setting(assigns) do
    ~H"""
    <section aria-labelledby="parts-heading">
      <h2 id="parts-heading">Transfers</h2>
      <p>
        A copy of a resident that this refuge sends to a partner holds the facts and the medical
        history always. It also holds these parts at first, and the person who sends it can
        change them for each transfer.
      </p>
      <p :if={@organisation.transfer_parts == []}>No other part.</p>
      <ul :if={@organisation.transfer_parts != []}>
        <li :for={part <- @organisation.transfer_parts}>{RescordWeb.TransferWords.part(part)}</li>
      </ul>

      <form :if={@can_change?} id="parts" phx-submit="save_parts">
        <fieldset>
          <legend>The parts of a copy at first</legend>
          <label :for={{part, words} <- RescordWeb.TransferWords.parts()}>
            <input
              type="checkbox"
              name="parts[keys][]"
              value={part}
              checked={part in @organisation.transfer_parts}
            />
            {words}
          </label>
        </fieldset>
        <footer><.button type="submit">Save the parts</.button></footer>
      </form>
    </section>
    """
  end
end
