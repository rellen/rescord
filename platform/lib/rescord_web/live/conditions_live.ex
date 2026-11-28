defmodule RescordWeb.ConditionsLive do
  @moduledoc """
  The conditions of the residents of an organisation, at
  `/o/<short name>/residents/conditions` (ADR 0083).

  The page says what the residents in care have now, by condition and by
  where they live, how many conditions started in each of the last months,
  and each condition of each resident in a list with a search, filters and
  a sort. Each member can open it: it reads as that member.

  The page reads only the values that it knows from what the browser sends,
  and makes no atom from it.
  """

  use RescordWeb, :live_view

  import RescordWeb.ConditionComponents

  alias Rescord.{Journal, Lists}
  alias RescordWeb.{JournalWords, ResidentWords}

  # The times that the form of the counts offers, in months.
  @months [3, 6, 12, 24]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, conditions} = Lists.values(:condition, options(socket))
    {:ok, now} = Journal.conditions_now(options(socket))

    {:ok,
     socket
     |> assign(
       page_title: "Conditions",
       conditions: Enum.map(conditions, &{to_string(&1.label), &1.id}),
       now: now
     )
     |> assign_started(6, nil)}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp assign_started(socket, months, condition_id) do
    {:ok, started} =
      Journal.conditions_started(months, [condition: condition_id] ++ options(socket))

    assign(socket,
      started: started,
      form:
        to_form(%{"months" => Integer.to_string(months), "condition_id" => condition_id || ""},
          as: :counts
        ),
      one_condition?: not is_nil(condition_id)
    )
  end

  @impl true
  def handle_event("count", %{"counts" => fields}, socket) when is_map(fields) do
    months = Enum.find(@months, 6, &(Integer.to_string(&1) == fields["months"]))

    # Only a condition of the list of this organisation.
    condition_id =
      Enum.find_value(socket.assigns.conditions, fn {_label, id} ->
        if id == fields["condition_id"], do: id
      end)

    {:noreply, assign_started(socket, months, condition_id)}
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp month_options,
    do: Enum.map(@months, &{"The last #{&1} months", Integer.to_string(&1)})

  # The rows of a list of counts.
  defp condition_rows(rows),
    do: Enum.map(rows, &%{label: to_string(&1.condition.label), count: &1.count})

  defp location_rows(rows, organisation) do
    Enum.map(rows, fn
      %{location: nil, count: count} ->
        %{label: "No place", count: count}

      %{location: location, count: count} ->
        %{
          label: location.name,
          count: count,
          to: ~p"/o/#{organisation.short_name}/housing/#{location.id}"
        }
    end)
  end

  defp month_rows(rows),
    do: Enum.map(rows, &%{label: JournalWords.month(&1.month), count: &1.count})

  # `9 conditions of 7 residents in care are not resolved.`
  defp now_words(%{conditions: 0}),
    do: "No resident in care has a condition that is not resolved."

  defp now_words(%{conditions: 1}), do: "1 condition of 1 resident in care is not resolved."

  defp now_words(%{conditions: conditions, residents: residents}) do
    of = if residents == 1, do: "1 resident", else: "#{residents} residents"
    "#{conditions} conditions of #{of} in care are not resolved."
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      inbox={@inbox}
      section={:residents}
    >
      <nav aria-label="Breadcrumb">
        <.link navigate={~p"/o/#{@organisation.short_name}/residents"}>Residents</.link>
      </nav>

      <.header icon={Icons.section(:conditions)}>
        Conditions
        <:subtitle>What the residents of {@organisation.name} have, and what they had</:subtitle>
      </.header>

      <section aria-labelledby="now-heading">
        <h2 id="now-heading">Now</h2>
        <p id="now-words">{now_words(@now)}</p>
        <h3 :if={@now.by_condition != []} id="now-by-condition-heading">By condition</h3>
        <.counts
          :if={@now.by_condition != []}
          id="now-by-condition"
          aria-labelledby="now-by-condition-heading"
          rows={condition_rows(@now.by_condition)}
        />
        <h3 :if={@now.by_location != []} id="now-by-location-heading">
          By where the residents live now
        </h3>
        <.counts
          :if={@now.by_location != []}
          id="now-by-location"
          aria-labelledby="now-by-location-heading"
          rows={location_rows(@now.by_location, @organisation)}
        />
      </section>

      <section aria-labelledby="started-heading">
        <h2 id="started-heading">New in each month</h2>
        <.form for={@form} id="counts" phx-change="count" phx-submit="count">
          <.input
            field={@form[:condition_id]}
            type="select"
            label="Condition"
            prompt="Each condition"
            options={@conditions}
          />
          <.input field={@form[:months]} type="select" label="Time" options={month_options()} />
        </.form>
        <h3 id="started-by-month-heading">Conditions that started in each month</h3>
        <.counts
          id="started-by-month"
          aria-labelledby="started-by-month-heading"
          rows={month_rows(@started.by_month)}
        />
        <h3
          :if={not @one_condition? and @started.by_condition != []}
          id="started-by-condition-heading"
        >
          The same conditions, by condition
        </h3>
        <.counts
          :if={not @one_condition? and @started.by_condition != []}
          id="started-by-condition"
          aria-labelledby="started-by-condition-heading"
          rows={condition_rows(@started.by_condition)}
        />
      </section>

      <section aria-labelledby="each-heading">
        <h2 id="each-heading">Each condition</h2>
        <Cinder.collection
          id="conditions"
          query={
            Journal.query_to_episodes(%{},
              load: [:state, :condition_label, :resident_name],
              query: [sort: [started_on: :desc]],
              actor: @current_user,
              tenant: @organisation
            )
          }
          actor={@current_user}
          tenant={@organisation}
        >
          <:col :let={episode} field="resident_name" label="Resident" sort search>
            <.link navigate={journal_path(@organisation, episode.resident_id, episode: episode.id)}>
              {episode.resident_name || "No name yet"}
            </.link>
            <small :if={episode.note}>{episode.note}</small>
          </:col>
          <:col
            :let={episode}
            field="condition_label"
            label="Condition"
            sort
            filter={[
              type: :select,
              prompt: "Any condition",
              options: Enum.map(@conditions, fn {label, _id} -> {label, label} end)
            ]}
          >
            <span data-label="Condition">{episode.condition_label}</span>
          </:col>
          <:col :let={episode} field="started_on" label="Started" sort filter={:date_range}>
            <span data-label="Started">{ResidentWords.date(episode.started_on)}</span>
          </:col>
          <:col :let={episode} field="ended_on" label="Last day" sort>
            <span data-label="Last day">{ResidentWords.date(episode.ended_on) || "Not yet"}</span>
          </:col>
          <:col
            :let={episode}
            field="state"
            label="State"
            filter={[
              type: :select,
              prompt: "Any state",
              options: [{"Ongoing", "ongoing"}, {"Resolved", "resolved"}]
            ]}
          >
            <.condition_state episode={episode} />
          </:col>
        </Cinder.collection>
      </section>
    </Layouts.app>
    """
  end
end
