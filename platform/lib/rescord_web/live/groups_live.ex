defmodule RescordWeb.GroupsLive do
  @moduledoc """
  The groups of an organisation, at `/o/<short name>/groups`.

  Each member sees the groups, each with the words that say how its members
  are related. A member makes a new group here, with its first members.
  """

  use RescordWeb, :live_view

  import RescordWeb.GroupComponents

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
      name: non_blank(fields["name"]),
      kind_id: non_blank(fields["kind_id"]),
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
           form: typed_form(fields, as: :group)
         )}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      section={:groups}
    >
      <.header>
        Groups
        <:subtitle>The residents that {@organisation.name} manages together</:subtitle>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <p :if={@groups == []}>There is no group yet.</p>
      <.groups_table :if={@groups != []} groups={@groups} organisation={@organisation} />

      <.new_group :if={@can_form?} form={@form} kinds={@kinds} residents={@residents} />
    </Layouts.app>
    """
  end
end
