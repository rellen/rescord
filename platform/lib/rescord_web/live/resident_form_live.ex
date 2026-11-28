defmodule RescordWeb.ResidentFormLive do
  @moduledoc """
  The form of a resident: a new one at `/o/<short name>/residents/new`, and
  a change at `/o/<short name>/residents/<id>/edit`.

  The form sends each fact of the resident in one action, `register` or
  `revise`. It offers the values of the lists of the organisation. A new
  resident can have an arrival, or it is expected.

  The page reads only the fields that it knows from what the browser sends,
  and makes no atom from it.
  """

  use RescordWeb, :live_view

  import RescordWeb.ResidentComponents

  alias Rescord.{Accounts, Lists, Residents}

  # A dimension of which a resident has one value, and its field.
  @one [species: "species_id", size_class: "size_class_id", coat: "coat_id"]
  # A dimension of which a resident has more than one value, and its field.
  @many [breed: "breed_ids", colour: "colour_ids", temperament: "temperament_ids"]

  @impl true
  def mount(params, _session, socket) do
    socket = assign(socket, problems: [])

    case socket.assigns.live_action do
      :new ->
        {:ok,
         socket
         |> assign(page_title: "New resident", resident: nil, lists: lists(socket, nil))
         |> assign_form(%{"sex" => "unknown", "desex_status" => "unknown"})}

      :edit ->
        case Residents.resident_with_facts(params["id"], options(socket)) do
          {:ok, %{} = resident} ->
            {:ok,
             socket
             |> assign(page_title: "Change #{resident.name || "a resident"}", resident: resident)
             |> assign(lists: lists(socket, resident))
             |> assign_form(fields_of(resident))}

          _no_resident ->
            {:ok,
             socket
             |> put_flash(:error, "There is no such resident.")
             |> redirect(to: ~p"/o/#{socket.assigns.organisation.short_name}/residents")}
        end
    end
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  # The values that the form offers for each list, as `{label, id}`. A
  # retired value is there only when the resident has it, so that a change
  # to another fact does not take it away.
  defp lists(socket, resident) do
    has = if resident, do: values_of(resident), else: MapSet.new()

    for {key, _field} <- @one ++ @many, into: %{} do
      {:ok, values} = Lists.values(key, options(socket))

      {key,
       for value <- values, not value.retired or MapSet.member?(has, value.id) do
         {to_string(value.label), value.id}
       end}
    end
  end

  defp values_of(resident) do
    MapSet.new(
      [resident.species_id, resident.size_class_id, resident.coat_id] ++
        Enum.map(resident.resident_breeds, & &1.breed_id) ++
        Enum.map(resident.resident_colours, & &1.colour_id) ++
        Enum.map(resident.resident_temperaments, & &1.temperament_id)
    )
  end

  defp assign_form(socket, fields) do
    fields = text_fields(fields)

    assign(socket, form: typed_form(fields, as: :resident), fields: fields)
  end

  defp fields_of(resident) do
    %{
      "name" => resident.name || "",
      "species_id" => resident.species_id,
      "sex" => Atom.to_string(resident.sex),
      "desex_status" => Atom.to_string(resident.desex_status),
      "born_on" => if(resident.born_on, do: Date.to_iso8601(resident.born_on), else: ""),
      "born_on_estimated" => to_string(resident.born_on_estimated),
      "size_class_id" => resident.size_class_id || "",
      "coat_id" => resident.coat_id || "",
      "markings" => resident.markings || "",
      "breed_ids" => Enum.map(resident.resident_breeds, & &1.breed_id),
      "colour_ids" => Enum.map(resident.resident_colours, & &1.colour_id),
      "temperament_ids" => Enum.map(resident.resident_temperaments, & &1.temperament_id)
    }
  end

  @impl true
  # A resident that came has come on a day, and most come on the day of the
  # intake: when a person chooses how the resident came and the date is
  # empty, the date is today in the organisation (ADR 0111). They change it
  # for a resident that came before.
  def handle_event("choose", %{"resident" => fields}, socket) when is_map(fields) do
    fields = text_fields(fields)

    fields =
      if non_blank(fields["arrival_kind"]) && !non_blank(fields["arrived_on"]),
        do:
          Map.put(
            fields,
            "arrived_on",
            Date.to_iso8601(Accounts.today(socket.assigns.organisation))
          ),
        else: fields

    {:noreply, assign_form(socket, fields)}
  end

  def handle_event("save", %{"resident" => fields}, socket) when is_map(fields) do
    facts = facts(fields)

    result =
      case socket.assigns.resident do
        nil ->
          fields |> arrival() |> Map.merge(facts) |> Residents.register_resident(options(socket))

        resident ->
          Residents.revise_resident(resident, facts, options(socket))
      end

    case result do
      {:ok, resident} ->
        words =
          if socket.assigns.resident,
            do: "The details are saved.",
            else: "The resident is registered."

        {:noreply,
         socket
         |> put_flash(:info, words)
         |> push_navigate(
           to: ~p"/o/#{socket.assigns.organisation.short_name}/residents/#{resident.id}"
         )}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(problems: Rescord.Accounts.error_messages(error))
         |> assign_form(fields)}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # The facts that both actions take.
  defp facts(fields) do
    %{
      name: non_blank(fields["name"]),
      species_id: non_blank(fields["species_id"]),
      sex: non_blank(fields["sex"]),
      desex_status: non_blank(fields["desex_status"]),
      born_on: non_blank(fields["born_on"]),
      born_on_estimated: fields["born_on_estimated"] == "true",
      size_class_id: non_blank(fields["size_class_id"]),
      coat_id: non_blank(fields["coat_id"]),
      markings: non_blank(fields["markings"]),
      breed_ids: ids(fields["breed_ids"]),
      colour_ids: ids(fields["colour_ids"]),
      temperament_ids: ids(fields["temperament_ids"])
    }
  end

  # The arrival of a new resident. With no kind and no date, it is expected.
  defp arrival(fields) do
    %{
      arrival_kind: non_blank(fields["arrival_kind"]),
      arrived_on: non_blank(fields["arrived_on"]),
      arrival_note: non_blank(fields["arrival_note"])
    }
  end

  # A group of check boxes with none set sends no field.
  defp ids(values) when is_list(values), do: Enum.filter(values, &is_binary/1)
  defp ids(_none), do: []

  defp chosen?(fields, field, id), do: id in List.wrap(fields[field])

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns, many: [breed: "Breed", colour: "Colour", temperament: "Temperament"])

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      inbox={@inbox}
      ruby={@ruby?}
      section={:residents}
    >
      <.header icon={Icons.section(:residents)}>
        <:crumb navigate={~p"/o/#{@organisation.short_name}/residents"}>Residents</:crumb>
        <:crumb
          :if={@resident}
          navigate={~p"/o/#{@organisation.short_name}/residents/#{@resident.id}"}
        >
          {@resident.name || "A resident with no name"}
        </:crumb>
        {@page_title}
        <:subtitle :if={is_nil(@resident)}>
          Each fact but the species can come later.
        </:subtitle>
      </.header>

      <.problems list={@problems} />

      <p :if={@lists.species == []} role="status">
        The list of species is empty, and a resident needs a species. An administrator adds
        values on <.link navigate={~p"/o/#{@organisation.short_name}/lists"}>the lists page</.link>.
      </p>

      <.form for={@form} id="resident" phx-change="choose" phx-submit="save">
        <.resident_fields form={@form} lists={@lists} />

        <fieldset :for={{key, legend} <- @many}>
          <legend>{legend}</legend>
          <p :if={@lists[key] == []}>
            This list has no value yet. An administrator adds them on <.link navigate={
              ~p"/o/#{@organisation.short_name}/lists"
            }>the lists page</.link>.
          </p>
          <label :for={{label, id} <- @lists[key]}>
            <input
              type="checkbox"
              name={"resident[#{key}_ids][]"}
              value={id}
              checked={chosen?(@fields, "#{key}_ids", id)}
            />
            {label}
          </label>
        </fieldset>

        <.arrival_fields :if={is_nil(@resident)} form={@form} />

        <footer>
          <.button type="submit" variant="primary">
            {if @resident, do: "Save the changes", else: "Record the resident"}
          </.button>
          <.link
            navigate={
              if @resident,
                do: ~p"/o/#{@organisation.short_name}/residents/#{@resident.id}",
                else: ~p"/o/#{@organisation.short_name}/residents"
            }
            data-variant="secondary"
          >
            Cancel
          </.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end
end
