defmodule RescordWeb.GroupComponents do
  @moduledoc """
  The parts of the pages of the groups (ADR 0028 and ADR 0037): the table of
  the groups, the members of a group, and the forms that shape a group.
  """

  use RescordWeb, :html

  alias Rescord.Residents

  @doc "The groups, each with how its members are related, its kind and its size."
  attr :groups, :any, required: true
  attr :organisation, :any, required: true

  def groups_table(assigns) do
    ~H"""
    <div data-scroll>
      <table>
        <thead>
          <tr>
            <th scope="col">Group</th>
            <th scope="col">How they are related</th>
            <th scope="col">Kind</th>
            <th scope="col">Members</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={group <- @groups}>
            <td>
              <.link navigate={~p"/o/#{@organisation.short_name}/groups/#{group.id}"}>
                {Residents.group_name(group)}
              </.link>
            </td>
            <td>{Residents.words(group) || "No relation is recorded"}</td>
            <td>{if group.kind, do: group.kind.label, else: "Not recorded"}</td>
            <td>{length(group.members)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc "The form of a new group, with its first members."
  attr :form, :any, required: true
  attr :kinds, :any, required: true
  attr :residents, :any, required: true

  def new_group(assigns) do
    ~H"""
    <details id="new-group">
      <summary>New group</summary>
      <.form for={@form} id="group" phx-submit="form">
        <.input field={@form[:name]} type="text" label="Name, if the group has one" maxlength="80" />
        <.input
          field={@form[:kind_id]}
          type="select"
          label="Kind"
          prompt="Not recorded"
          options={@kinds}
        />
        <fieldset>
          <legend>Members</legend>
          <p :if={@residents == []}>There is no resident yet.</p>
          <label :for={{name, id} <- @residents}>
            <input type="checkbox" name="group[resident_ids][]" value={id} />
            {name}
          </label>
        </fieldset>
        <footer><.button type="submit">Make the group</.button></footer>
      </.form>
    </details>
    """
  end

  @doc "The form that changes the name, the kind and the words of a group."
  attr :form, :any, required: true
  attr :kinds, :any, required: true

  def group_form(assigns) do
    ~H"""
    <details id="change-group">
      <summary>Change the group</summary>
      <.form for={@form} id="group" phx-submit="revise">
        <.input
          field={@form[:name]}
          type="text"
          label="Name, if the group has one"
          maxlength="80"
        />
        <.input
          field={@form[:kind_id]}
          type="select"
          label="Kind"
          prompt="Not recorded"
          options={@kinds}
        />
        <.input
          field={@form[:description]}
          type="text"
          label="How they are related, in your words. Leave it empty for the words of Rescord"
          maxlength="200"
        />
        <footer><.button type="submit">Save the group</.button></footer>
      </.form>
    </details>
    """
  end

  @doc "The facts of a group, and where it lives."
  attr :group, :any, required: true
  attr :home, :any, required: true
  attr :organisation, :any, required: true
  attr :role, :any, required: true
  attr :form, :any, required: true
  attr :kinds, :any, required: true

  def about_group(assigns) do
    ~H"""
    <section aria-labelledby="about-heading">
      <h2 id="about-heading">About</h2>
      <.list>
        <:item title="Kind">{if @group.kind, do: @group.kind.label, else: "Not recorded"}</:item>
        <:item title="Lives in">
          <.link
            :if={@home}
            navigate={~p"/o/#{@organisation.short_name}/housing/#{@home.location_id}"}
          >{@home.location.name}</.link>
          <span :if={is_nil(@home)}>No place in the housing yet</span>
        </:item>
        <:item title="How they are related">
          {Residents.words(@group) || "No relation is recorded"}
          <small :if={@group.description}>(the words of a member)</small>
        </:item>
      </.list>

      <.group_form :if={can?(@role, :group, :revise)} form={@form} kinds={@kinds} />
    </section>
    """
  end

  @doc "The form that takes a member out of a group, at the time that it left."
  attr :member, :any, required: true

  def leave_form(assigns) do
    ~H"""
    <details id={"leave-details-#{@member.id}"}>
      <summary>Take out</summary>
      <form id={"leave-#{@member.id}"} phx-submit="leave">
        <input type="hidden" name="member_id" value={@member.id} />
        <.input
          id={"leave-#{@member.id}-at"}
          name="leave[at]"
          type="datetime-local"
          label={"When #{@member.resident.name || "the resident with no name"} left the group, if not now"}
          value=""
        />
        <.button type="submit">
          Take {@member.resident.name || "the resident with no name"} out of the group
        </.button>
      </form>
    </details>
    """
  end

  @doc "A member of a group, with the form that takes it out."
  attr :organisation, :any, required: true
  attr :member, :any, required: true
  attr :role, :any, required: true

  def member_item(assigns) do
    ~H"""
    <li>
      <.link navigate={~p"/o/#{@organisation.short_name}/residents/#{@member.resident_id}"}>
        {@member.resident.name || "No name yet"}
      </.link>
      <.leave_form :if={can?(@role, :group_member, :leave)} member={@member} />
    </li>
    """
  end

  @doc "The form that adds a resident to a group, at the time that it joined."
  attr :join_form, :any, required: true
  attr :others, :any, required: true

  def join_form(assigns) do
    ~H"""
    <details id="add-member">
      <summary>Add a member</summary>
      <.form for={@join_form} id="member" phx-submit="join">
        <.input
          field={@join_form[:resident_id]}
          type="select"
          label="Resident"
          prompt="Choose"
          options={@others}
          required
        />
        <.input
          field={@join_form[:at]}
          type="datetime-local"
          label="When it joined the group, if not now"
        />
        <footer><.button type="submit">Add to the group</.button></footer>
      </.form>
    </details>
    """
  end

  @doc "The members of a group."
  attr :group, :any, required: true
  attr :organisation, :any, required: true
  attr :role, :any, required: true
  attr :others, :any, required: true
  attr :join_form, :any, required: true

  def group_members(assigns) do
    ~H"""
    <section aria-labelledby="members-heading">
      <h2 id="members-heading">Members</h2>
      <p :if={@group.members == []}>The group has no member.</p>
      <ul :if={@group.members != []}>
        <.member_item
          :for={member <- @group.members}
          organisation={@organisation}
          member={member}
          role={@role}
        />
      </ul>

      <.join_form
        :if={can?(@role, :group_member, :join) and @others != []}
        join_form={@join_form}
        others={@others}
      />
    </section>
    """
  end

  @doc "The closing of a group."

  def close_group(assigns) do
    ~H"""
    <details id="close-group">
      <summary>Close this group</summary>
      <p>Close a group that is no more. Its history stays.</p>
      <.button phx-click="close">Close the group</.button>
    </details>
    """
  end

  @doc "The part of the page that closes a group."

  def close_group_section(assigns) do
    ~H"""
    <section aria-labelledby="close-heading">
      <h2 id="close-heading">Close</h2>
      <.close_group />
    </section>
    """
  end

  def can?(role, subject, action), do: Residents.role_can?(role, subject, action)
end
