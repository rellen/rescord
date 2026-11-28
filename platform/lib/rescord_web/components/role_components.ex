defmodule RescordWeb.RoleComponents do
  @moduledoc """
  The parts of the page of the roles (ADR 0037 and ADR 0040): the list of
  the roles, and the form of a role, with a box for each power in the
  fieldset of its area of work.
  """

  use RescordWeb, :html

  alias RescordWeb.RoleWords

  @doc "The roles, each with its members, its powers, and the forms that change it."
  attr :roles, :list, required: true
  attr :counts, :map, required: true
  attr :can_revise?, :boolean, required: true
  attr :can_remove?, :boolean, required: true
  attr :refused, :any, required: true
  attr :problems, :list, required: true

  def roles_list(assigns) do
    ~H"""
    <section aria-labelledby="roles-heading">
      <h2 id="roles-heading">The roles</h2>
      <article :for={role <- @roles} id={"role-#{role.id}"} aria-labelledby={"role-#{role.id}-name"}>
        <header>
          <h3 id={"role-#{role.id}-name"}>{role.name}</h3>
          <small>{members_words(Map.get(@counts, role.id, 0))}</small>
        </header>
        <p :if={role.powers == []}>This role reads, and changes nothing.</p>
        <ul :if={role.powers != []}>
          <li :for={power <- role.powers}>{RoleWords.power(power)}</li>
        </ul>

        <details
          :if={@can_revise?}
          id={"revise-details-#{role.id}"}
          open={refused_role?(@refused, role)}
        >
          <summary><.icon name="pencil" /> Change the role {role.name}</summary>
          <.role_form
            id={"revise-#{role.id}"}
            event="revise"
            role_id={role.id}
            fields={fields_of(@refused, role)}
            button={"Save the role #{role.name}"}
            problems={if refused_role?(@refused, role), do: @problems, else: []}
          />
        </details>

        <.button
          :if={@can_remove? and is_nil(role.key) and Map.get(@counts, role.id, 0) == 0}
          phx-click="remove"
          phx-value-id={role.id}
          aria-label={"Remove the role #{role.name}"}
        >
          <.icon name="trash" /> Remove
        </.button>
      </article>
    </section>
    """
  end

  @doc "The form of a new role, in a part of the page that is closed at first."
  attr :refused, :any, required: true
  attr :problems, :list, required: true

  def new_role(assigns) do
    ~H"""
    <details id="new-role" open={match?({:define, _fields}, @refused)}>
      <summary><.icon name="plus" /> New role</summary>
      <.role_form
        id="define"
        event="define"
        role_id={nil}
        fields={
          case @refused do
            {:define, fields} -> fields
            _other -> %{"name" => "", "powers" => []}
          end
        }
        button="Add the role"
        problems={if match?({:define, _fields}, @refused), do: @problems, else: []}
      />
    </details>
    """
  end

  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :role_id, :any, required: true
  attr :fields, :map, required: true
  attr :button, :string, required: true
  attr :problems, :list, required: true

  # The form of a role: its name, and a box for each power.
  def role_form(assigns) do
    assigns = assign(assigns, chosen: List.wrap(assigns.fields["powers"]))

    ~H"""
    <form id={@id} phx-submit={@event}>
      <.problems list={@problems} />
      <input :if={@role_id} type="hidden" name="role_id" value={@role_id} />
      <.input
        id={"#{@id}-name"}
        name="role[name]"
        type="text"
        label="Name"
        value={@fields["name"]}
        maxlength="60"
        required
      />
      <fieldset :for={{area, powers} <- RoleWords.areas()} id={"#{@id}-#{area_id(area)}"}>
        <legend>{area}</legend>
        <label :for={power <- powers}>
          <input
            type="checkbox"
            name="role[powers][]"
            value={power}
            checked={Atom.to_string(power) in @chosen}
          />
          {RoleWords.power(power)}
        </label>
      </fieldset>
      <footer><.button type="submit">{@button}</.button></footer>
    </form>
    """
  end

  # Whether the action refused the form of this role.
  defp refused_role?({:revise, id, _fields}, %{id: id}), do: true
  defp refused_role?(_refused, _role), do: false

  @doc "The number of members of a role, in words."
  def members_words(0), do: "No member has this role."
  def members_words(1), do: "1 member has this role."
  def members_words(count), do: "#{count} members have this role."

  # The fields of the form of a role: what the person sent when the action
  # refused it, or the role as it is.
  defp fields_of({:revise, id, fields}, %{id: id}), do: fields

  defp fields_of(_refused, role),
    do: %{"name" => to_string(role.name), "powers" => Enum.map(role.powers, &Atom.to_string/1)}

  defp area_id(area), do: area |> String.downcase() |> String.replace(~r/[^a-z]+/, "-")
end
