defmodule RescordWeb.PrivacyRequestLive do
  @moduledoc """
  One request to erase data, at `/o/<short name>/privacy/<id>` (ADR 0105).

  The person whose request it is reads it. A person whose role has the
  power `privacy` reads each one, and, while it waits, erases the data,
  extends the day that it is due, refuses it with a reason, or records
  that the person withdrew it. After an erasure of a request by letter,
  that person records the day of the answer. The erasure says first what
  goes, what stays and what Rescord cannot reach, and asks about the
  comments of the person. Only a root user erases a member whose role
  can change the members or work on privacy (`Rescord.Privacy.erasable?/2`).
  """

  use RescordWeb, :live_view

  import RescordWeb.PrivacyComponents

  alias Rescord.{Accounts, Privacy}
  alias RescordWeb.ResidentWords

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Privacy.request(id, options(socket)) do
      {:ok, %{} = request} ->
        {:ok,
         socket
         |> assign(page_title: "A request to erase data", problems: [])
         |> assign(today: Accounts.today(socket.assigns.organisation))
         |> assign(can_manage?: Privacy.role_can?(socket.assigns.role, :extend))
         |> assign_request(request)}

      _none ->
        {:ok,
         socket
         |> put_flash(:error, "There is no such request.")
         |> push_navigate(to: ~p"/o/#{socket.assigns.organisation.short_name}/privacy")}
    end
  end

  defp options(socket),
    do: [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]

  defp assign_request(socket, request) do
    member = member(request, socket)

    assign(socket,
      request: request,
      people: Accounts.labels(options(socket)),
      erasable?: member != nil and Privacy.erasable?(member, options(socket)),
      hold_until: Privacy.hold_until(request.user_id, socket.assigns.organisation),
      erase_form: to_form(%{"kept" => "", "sure" => "false"}, as: :erase),
      extend_form:
        to_form(%{"extended_to" => "", "extension_reason" => "", "told_of_extension_on" => ""},
          as: :extend
        ),
      refuse_form: to_form(%{"refusal_reason" => ""}, as: :refuse),
      told_form: to_form(%{"told_on" => Date.to_iso8601(socket.assigns.today)}, as: :told)
    )
  end

  defp member(request, socket) do
    case Accounts.member_with_former(request.member_id,
           tenant: socket.assigns.organisation,
           authorize?: false
         ) do
      {:ok, %{} = member} -> member
      _none -> nil
    end
  end

  @impl true
  def handle_event("erase", %{"erase" => %{"sure" => "true"} = params}, socket) do
    choices = %{keep_comments: params["comments"] == "keep", kept: params["kept"]}

    case Privacy.erase(socket.assigns.request, choices, options(socket)) do
      {:ok, done} ->
        {:noreply,
         socket
         |> assign(problems: [])
         |> assign_request(done)
         |> put_flash(
           :info,
           "The data is erased. The records name the person Former member #{done.former_number}."
         )}

      {:error, error} ->
        {:noreply, assign(socket, problems: erase_problems(error))}
    end
  end

  def handle_event("erase", _params, socket),
    do: {:noreply, assign(socket, problems: ["Tick the box to say that you understand"])}

  def handle_event("extend", %{"extend" => params}, socket) when is_map(params) do
    act(
      socket,
      &Privacy.extend_request(&1, blank_to_nil(params), &2),
      "The request is due later now."
    )
  end

  def handle_event("refuse", %{"refuse" => params}, socket) when is_map(params) do
    act(socket, &Privacy.refuse_request(&1, blank_to_nil(params), &2), "The request is refused.")
  end

  def handle_event("withdraw", _params, socket) do
    act(socket, &Privacy.withdraw_request(&1, %{}, &2), "The request is withdrawn.")
  end

  def handle_event("told", %{"told" => %{"told_on" => day}}, socket) when is_binary(day) do
    act(socket, &Privacy.note_told(&1, day, &2), "The day of the answer is recorded.")
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp act(socket, action, words) do
    case action.(socket.assigns.request, options(socket)) do
      {:ok, request} ->
        {:noreply,
         socket |> assign(problems: []) |> assign_request(request) |> put_flash(:info, words)}

      {:error, error} ->
        {:noreply, assign(socket, problems: Accounts.error_messages(error))}
    end
  end

  defp blank_to_nil(params),
    do: Map.new(params, fn {key, value} -> {key, if(value == "", do: nil, else: value)} end)

  defp erase_problems(:forbidden),
    do: ["Only a root user erases a member who can change the members or work on privacy"]

  defp erase_problems(:closed), do: ["The request is closed already"]
  defp erase_problems(:not_found), do: ["The member of the request is gone"]
  defp erase_problems(error), do: Accounts.error_messages(error)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      inbox={@inbox}
      ruby={@ruby?}
      section={:members}
    >
      <.header icon={Icons.section(:privacy)}>
        <:crumb navigate={~p"/o/#{@organisation.short_name}/privacy"}>Privacy</:crumb>
        A request to erase data
        <:subtitle>
          The data of {person(@people, @request)} in {@organisation.name}
        </:subtitle>
      </.header>

      <.problems list={@problems} />

      <.facts request={@request} organisation={@organisation} today={@today} people={@people} />

      <%= if @can_manage? and @request.state == :received do %>
        <.erasure
          :if={@erasable?}
          hold_until={@hold_until}
          form={@erase_form}
          organisation={@organisation}
        />
        <p :if={not @erasable?} id="not-erasable">
          Only a root user erases a member whose role can change the members or work on privacy.
        </p>

        <section id="extend" aria-labelledby="extend-heading">
          <h2 id="extend-heading">Extend</h2>
          <p>
            A request that is complex, or one of many from the person, can wait at most two
            more months. Tell the person, with the reason, inside the first month.
          </p>
          <.form for={@extend_form} id="extend-form" phx-submit="extend">
            <.input
              field={@extend_form[:extended_to]}
              type="date"
              label="The new day it is due"
              required
            />
            <.input
              field={@extend_form[:extension_reason]}
              type="text"
              label="Why"
              maxlength="1000"
              required
            />
            <.input
              field={@extend_form[:told_of_extension_on]}
              type="date"
              label="The day you told the person"
              required
            />
            <footer><.button type="submit">Extend the request</.button></footer>
          </.form>
        </section>

        <section id="refuse" aria-labelledby="refuse-heading">
          <h2 id="refuse-heading">Refuse</h2>
          <p>
            A request that is manifestly unfounded or excessive, or that another reason stops,
            is refused with words that show why. Tell the person, and how they can complain.
          </p>
          <.form for={@refuse_form} id="refuse-form" phx-submit="refuse">
            <.input
              field={@refuse_form[:refusal_reason]}
              type="textarea"
              label="Why you refuse"
              maxlength="2000"
              required
            />
            <footer><.button type="submit">Refuse the request</.button></footer>
          </.form>
        </section>

        <section id="withdraw" aria-labelledby="withdraw-heading">
          <h2 id="withdraw-heading">Withdrawn</h2>
          <p>The person told you that they no longer ask.</p>
          <.confirm id="withdraw-step" summary="Record that it is withdrawn" icon="x-mark">
            <p>The request closes, and nothing is erased.</p>
            <.button id="withdraw-request" variant="danger" phx-click="withdraw">
              Record that the request is withdrawn
            </.button>
          </.confirm>
        </section>
      <% end %>

      <section
        :if={
          @can_manage? and @request.state == :done and @request.how_received == :letter and
            is_nil(@request.told_on)
        }
        id="told"
        aria-labelledby="told-heading"
      >
        <h2 id="told-heading">Answer by letter</h2>
        <p>
          The request came by letter, so Rescord sent no email. Write to the person what was
          erased and what stays, then record the day here.
        </p>
        <.form for={@told_form} id="told-form" phx-submit="told">
          <.input field={@told_form[:told_on]} type="date" label="The day you answered" required />
          <footer><.button type="submit">Record the answer</.button></footer>
        </.form>
      </section>

      <p :if={@request.state == :done and @request.how_received != :letter}>
        Rescord emails the person what was erased and what stays. The address stays in the
        queue of the email for one day after it went{if @request.told_on,
          do: ", on #{ResidentWords.date(@request.told_on)}",
          else: ""}.
      </p>
    </Layouts.app>
    """
  end
end
