defmodule RescordWeb.GroupMeasurementsLive do
  @moduledoc """
  One kind of measurement for each member of a group, at
  `/o/<short name>/groups/<id>/measurements` (ADR 0080): the weights of a
  litter.

  Each member has a tile with its newest value, its change, and a small
  chart with its line in front of the lines of the other members. Each
  tile has the same scale, so the eye compares two tiles.

  `?kind=<id>` chooses the kind, and `?range=90` the time. With no kind the
  page shows the kind that the members have the most measurements of.
  """

  use RescordWeb, :live_view

  import RescordWeb.MeasurementComponents

  alias Rescord.{Accounts, Journal, Residents}
  alias Rescord.Journal.Series
  alias RescordWeb.{Chart, MeasurementWords, ResidentWords}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    options = options(socket)

    with true <- is_binary(id),
         {:ok, %{} = group} <- Residents.group_with_facts(id, options) do
      residents = Enum.map(group.members, & &1.resident)
      {:ok, series} = Journal.series_of(Enum.map(residents, & &1.id), options)

      {:ok,
       assign(socket,
         group: group,
         page_title: "Measurements of #{Residents.group_name(group)}",
         residents: residents,
         series: series,
         kinds: kinds(series)
       )}
    else
      _no_group ->
        {:ok,
         socket
         |> put_flash(:error, "There is no such group.")
         |> redirect(to: ~p"/o/#{socket.assigns.organisation.short_name}/groups")}
    end
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  # The kinds that the members have a measurement of, each as its id, its
  # name and the number of its measurements, in the order of the names.
  defp kinds(series) do
    series
    |> Map.values()
    |> List.flatten()
    |> Enum.group_by(&{&1.kind_id, &1.label}, &length(&1.points ++ &1.others))
    |> Enum.map(fn {{id, label}, counts} -> %{id: id, label: label, count: Enum.sum(counts)} end)
    |> Enum.sort_by(&String.downcase(&1.label))
  end

  @impl true
  def handle_params(params, _uri, socket) do
    kinds = socket.assigns.kinds
    range = if days(params["range"]), do: params["range"], else: "all"

    # The kind of the address, when the members have it. With none, the kind
    # with the most measurements.
    kind =
      Enum.find(kinds, &(&1.id == params["kind"])) ||
        Enum.max_by(kinds, & &1.count, fn -> nil end)

    {:noreply, socket |> assign(range: range, kind: kind) |> assign_members()}
  end

  # Each member with its series of the kind, in the unit of the member that
  # was measured last, and the points of the time range.
  defp assign_members(%{assigns: %{kind: nil}} = socket),
    do: assign(socket, members: [], scale: nil, unit: nil)

  defp assign_members(socket) do
    %{residents: residents, series: series, kind: kind, organisation: organisation} =
      socket.assigns

    from = since(organisation, days(socket.assigns.range))

    of_kind =
      for resident <- residents do
        {resident, Enum.find(Map.get(series, resident.id, []), &(&1.kind_id == kind.id))}
      end

    # The series that the others follow: the one with the newest point.
    lead =
      of_kind
      |> Enum.map(&elem(&1, 1))
      |> Enum.filter(&(&1 && &1.points != []))
      |> Enum.max_by(&DateTime.to_unix(Series.newest(&1).at, :microsecond), fn -> nil end)

    members =
      for {resident, own} <- of_kind do
        case own && lead && Series.like(own, lead) do
          {:ok, like} ->
            %{resident: resident, series: like, shown: Series.since(like, from), charted?: true}

          :error ->
            %{resident: resident, series: own, shown: nil, charted?: false}

          nil ->
            %{resident: resident, series: nil, shown: nil, charted?: false}
        end
      end

    points = Enum.flat_map(members, &((&1.shown && &1.shown.points) || []))

    assign(socket, members: members, scale: Chart.scale(points), unit: lead)
  end

  defp since(_organisation, nil), do: nil

  defp since(organisation, days) do
    {from, _next_day} =
      Accounts.day_range(organisation, Date.add(Accounts.today(organisation), -days))

    from
  end

  @impl true
  def handle_event("kind", %{"kind" => id}, socket) when is_binary(id) do
    {:noreply,
     push_patch(socket,
       to: page_path(socket.assigns.organisation, socket.assigns.group, id, socket.assigns.range)
     )}
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # The address of the page with a kind and a time range.
  defp page_path(organisation, group, kind_id, range) do
    query = if range == "all", do: [kind: kind_id], else: [kind: kind_id, range: range]
    ~p"/o/#{organisation.short_name}/groups/#{group.id}/measurements?#{query}"
  end

  # What each tile has in common: the unit, and the scale in value and in time.
  defp scale_words(nil, lead, _organisation), do: unit_words(lead)

  defp scale_words(%Chart.Scale{} = scale, lead, organisation) do
    date = &ResidentWords.date(Accounts.local_date(organisation, &1))
    lowest = MeasurementWords.value(lead, List.first(scale.ticks))
    highest = MeasurementWords.value(lead, List.last(scale.ticks))

    "#{unit_words(lead)} Each chart is from #{lowest} to #{highest}, " <>
      "and from #{date.(scale.from)} to #{date.(scale.to)}."
  end

  defp unit_words(%Series{unit_label: nil} = lead), do: "#{lead.label}."
  defp unit_words(%Series{unit_label: unit} = lead), do: "#{lead.label} in #{unit}."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      inbox={@inbox}
      section={:groups}
    >
      <nav aria-label="Breadcrumb">
        <.link navigate={~p"/o/#{@organisation.short_name}/groups/#{@group.id}"}>{Residents.group_name(
          @group
        )}</.link>
      </nav>

      <.header icon={Icons.section(:measurements)}>
        Measurements of {Residents.group_name(@group)}
        <:subtitle>Each member, with the others behind it</:subtitle>
      </.header>

      <p :if={@residents == []}>The group has no member.</p>
      <p :if={@residents != [] and @kinds == []}>No measurement of a member is recorded.</p>

      <form :if={length(@kinds) > 1} id="kind" phx-change="kind">
        <.input
          id="kind-choice"
          name="kind"
          type="select"
          label="Kind of measurement"
          value={@kind.id}
          options={Enum.map(@kinds, &{&1.label, &1.id})}
        />
      </form>

      <.range_choice
        :if={@kind}
        chosen={days(@range)}
        path={&page_path(@organisation, @group, @kind.id, &1)}
      />

      <p :if={@unit} data-scale>{scale_words(@scale, @unit, @organisation)}</p>

      <.member_tiles
        :if={@kind}
        members={@members}
        scale={@scale}
        organisation={@organisation}
        range={@range}
      />
    </Layouts.app>
    """
  end
end
