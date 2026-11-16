defmodule RescordWeb.GroupsLive do
  @moduledoc """
  The groups of an organisation, at `/o/<short name>/groups`.

  Each member sees the groups, each with the words that say how its members
  are related. A member makes a new group here, with its first members.
  """

  use RescordWeb, :live_view

  alias Rescord.{Lists, Residents}

  @impl true
  def mount(_params, _session, socket) do
    options = options(socket)
    {:ok, groups} = Residents.groups_with_facts(options)
    {:ok, residents} = Residents.residents([load: [:name]] ++ options)
    {:ok, kinds} = Lists.offered_values(:group_kind, options)

    {:ok,
     assign(socket,
       page_title: "Groups",
       problems: [],
       groups: Enum.sort_by(groups, &Residents.group_name/1),
       residents: residents |> Enum.map(&{&1.name || "No name yet", &1.id}) |> Enum.sort(),
       kinds: Enum.map(kinds, &{to_string(&1.label), &1.id}),
       can_form?: Residents.role_can?(socket.assigns.role, :group, :form),
       form: to_form(%{"name" => "", "kind_id" => ""}, as: :group)
     )}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  @impl true
  def handle_event("form", %{"group" => fields}, socket) when is_map(fields) do
    attributes = %{
      name: text(fields["name"]),
      kind_id: text(fields["kind_id"]),
      resident_ids: Enum.filter(List.wrap(fields["resident_ids"]), &is_binary/1)
    }

    case Residents.form_group(attributes, options(socket)) do
      {:ok, group} ->
        {:noreply,
         push_navigate(socket,
           to: ~p"/o/#{socket.assigns.organisation.short_name}/groups/#{group.id}"
         )}

      {:error, error} ->
        {:noreply,
         assign(socket,
           problems: Rescord.Accounts.error_messages(error),
           form: to_form(fields, as: :group)
         )}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp text(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp text(_other), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} organisation={@organisation}>
      <.header>
        Groups
        <:subtitle>The residents that {@organisation.name} manages together</:subtitle>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <p :if={@groups == []}>There is no group yet.</p>
      <div :if={@groups != []} data-scroll>
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

      <details :if={@can_form?}>
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
    </Layouts.app>
    """
  end
end
