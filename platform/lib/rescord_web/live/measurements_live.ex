defmodule RescordWeb.MeasurementsLive do
  @moduledoc """
  The measurements of one resident over time, at
  `/o/<short name>/residents/<id>/measurements` (ADR 0080).

  The page has a card for each kind of measurement that the resident has:
  the newest value, its change, a chart and a table. `?range=90` shows the
  last 90 days, and no range shows each measurement. A person who can write
  to the journal records a measurement here: it is a journal entry.

  A press on a point of a chart chooses it, and the page writes it in
  words. The page reads only the fields that it knows from what the browser
  sends, and makes no atom from it.
  """

  use RescordWeb, :live_view

  import RescordWeb.MeasurementComponents

  alias Rescord.{Accounts, Journal, Lists, Residents}
  alias Rescord.Journal.Series

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    options = options(socket)

    with true <- is_binary(id),
         {:ok, %{} = resident} <- Residents.resident(id, [load: [:name]] ++ options) do
      {:ok,
       socket
       |> assign(
         resident: resident,
         page_title: "Measurements of #{name(resident)}",
         problems: [],
         selected: nil,
         can_write?: Journal.role_can_write?(socket.assigns.role)
       )
       |> assign_lists()
       |> assign_series()
       |> assign_form(%{})}
    else
      _no_resident ->
        {:ok,
         socket
         |> put_flash(:error, "There is no such resident.")
         |> redirect(to: ~p"/o/#{socket.assigns.organisation.short_name}/residents")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    range = if days(params["range"]), do: params["range"], else: "all"
    {:noreply, socket |> assign(range: range, selected: nil) |> assign_shown()}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  # The kinds and the units that the form offers, and the units of each
  # kind that names some.
  defp assign_lists(%{assigns: %{can_write?: false}} = socket),
    do: assign(socket, kinds: [], all_units: [], units_of: %{})

  defp assign_lists(socket) do
    options = options(socket)
    {:ok, kinds} = Lists.offered_values(:measure_kind, options)
    {:ok, units} = Lists.offered_values(:unit, options)

    assign(socket,
      kinds: Enum.map(kinds, &{to_string(&1.label), &1.id}),
      all_units: Enum.map(units, &{to_string(&1.label), &1.id}),
      units_of: for(kind <- kinds, kind.unit_ids != [], into: %{}, do: {kind.id, kind.unit_ids})
    )
  end

  defp assign_series(socket) do
    {:ok, series} = Journal.series(socket.assigns.resident.id, options(socket))
    assign(socket, series: series)
  end

  # The series of the time range: each with its points from the first
  # instant of the range on.
  defp assign_shown(socket) do
    from = since(socket.assigns.organisation, days(socket.assigns.range))
    assign(socket, shown: Map.new(socket.assigns.series, &{&1.kind_id, Series.since(&1, from)}))
  end

  defp since(_organisation, nil), do: nil

  defp since(organisation, days) do
    {from, _next_day} =
      Accounts.day_range(organisation, Date.add(Accounts.today(organisation), -days))

    from
  end

  # The units that the form offers: those of the chosen kind, or each unit
  # when the kind names none.
  defp unit_options(socket, kind_id) do
    case Map.get(socket.assigns.units_of, kind_id) do
      nil -> socket.assigns.all_units
      ids -> Enum.filter(socket.assigns.all_units, fn {_label, id} -> id in ids end)
    end
  end

  # A form with the kind that the person chose. When the kind changes, the
  # unit is the unit of the newest measurement of that kind, when the form
  # offers it: a person who weighs in grams does not choose grams each day.
  defp assign_form(socket, fields) do
    fields = typed_fields(fields)
    kind_id = fields["measure_kind_id"]
    units = unit_options(socket, kind_id)

    fields =
      if kind_id != socket.assigns[:form_kind],
        do: Map.put(fields, "unit_id", usual_unit(socket, kind_id, units)),
        else: fields

    assign(socket,
      form: typed_form(fields, as: :measurement),
      form_kind: kind_id,
      units: units
    )
  end

  defp usual_unit(socket, kind_id, units) do
    with %Series{unit_id: unit_id} <- Enum.find(socket.assigns.series, &(&1.kind_id == kind_id)),
         true <- Enum.any?(units, fn {_label, id} -> id == unit_id end) do
      unit_id
    else
      _none -> ""
    end
  end

  @impl true
  def handle_event("choose", %{"measurement" => fields}, socket) when is_map(fields) do
    {:noreply, assign_form(socket, fields)}
  end

  def handle_event("record", %{"measurement" => fields}, socket) when is_map(fields) do
    fields = typed_fields(fields)

    with {:ok, instant} <- Accounts.instant(socket.assigns.organisation, fields["at"]),
         {:ok, _entry} <-
           Journal.write_entry(
             %{
               resident_id: socket.assigns.resident.id,
               kind: :measurement,
               measure_kind_id: non_blank(fields["measure_kind_id"]),
               value: non_blank(fields["value"]),
               unit_id: non_blank(fields["unit_id"]),
               note: non_blank(fields["note"]),
               happened_at: instant
             },
             options(socket)
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "The measurement is recorded.")
       |> push_navigate(
         to: page_path(socket.assigns.organisation, socket.assigns.resident, socket.assigns.range)
       )}
    else
      {:error, words} when is_binary(words) ->
        {:noreply, socket |> assign(problems: [words]) |> assign_form(fields)}

      {:error, error} ->
        {:noreply,
         socket |> assign(problems: Accounts.error_messages(error)) |> assign_form(fields)}
    end
  end

  # A press on a point of a chart chooses it, and a press on the chosen
  # point lets it go. Only a point of this page: the page has them in hand.
  def handle_event("pick", %{"point" => id}, socket) when is_binary(id) do
    on_page? =
      Enum.any?(socket.assigns.shown, fn {_kind, series} ->
        Enum.any?(series.points, &(&1.entry_id == id))
      end)

    selected = if on_page? and socket.assigns.selected != id, do: id

    {:noreply, assign(socket, selected: selected)}
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # The address of the page with a time range. No range is each measurement.
  defp page_path(organisation, resident, "all"),
    do: ~p"/o/#{organisation.short_name}/residents/#{resident.id}/measurements"

  defp page_path(organisation, resident, range),
    do: ~p"/o/#{organisation.short_name}/residents/#{resident.id}/measurements?#{[range: range]}"

  defp name(resident), do: resident.name || "a resident with no name"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      section={:residents}
    >
      <nav aria-label="Breadcrumb">
        <.link navigate={~p"/o/#{@organisation.short_name}/residents/#{@resident.id}"}>{name(
          @resident
        )}</.link>
      </nav>

      <.header>
        Measurements of {name(@resident)}
        <:subtitle>Each kind of measurement over time</:subtitle>
        <:actions>
          <.link
            navigate={~p"/o/#{@organisation.short_name}/residents/#{@resident.id}/journal"}
            data-variant="secondary"
          >
            Journal
          </.link>
        </:actions>
      </.header>

      <.problems list={@problems} />

      <.range_choice
        :if={@series != []}
        chosen={days(@range)}
        path={&page_path(@organisation, @resident, &1)}
      />

      <.record_form :if={@can_write?} form={@form} kinds={@kinds} units={@units} />

      <p :if={@series == []}>No measurement is recorded.</p>

      <div :if={@series != []} data-charts>
        <.measure
          :for={series <- @series}
          series={series}
          shown={@shown[series.kind_id]}
          organisation={@organisation}
          resident={@resident}
          selected={@selected}
        />
      </div>
    </Layouts.app>
    """
  end
end
