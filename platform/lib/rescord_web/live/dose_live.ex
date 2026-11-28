defmodule RescordWeb.DoseLive do
  @moduledoc """
  The dose calculator, at `/o/<short name>/tools/dose` (ADR 0072): a body
  weight times a dose rate, and with the strength of a product the volume
  or the number of tablets that holds the dose.

  The page is an aid to arithmetic (`Rescord.Dosage`). It knows no
  medication, stores nothing, shows each step of its working, and says at
  all times to check the result with a vet. Each member of the organisation
  can open it.

  The result is never stale. The page calculates when the person presses
  Calculate, and a change to a field takes the result away until they
  press it again.

  The page reads only the fields that it knows from what the browser
  sends, and makes no atom from it.
  """

  use RescordWeb, :live_view

  import RescordWeb.ToolComponents

  alias Rescord.Dosage
  alias RescordWeb.ToolWords

  # The fields of the form, each with the key that `Rescord.Dosage.read/1`
  # knows it by.
  @fields [
    {"weight", :weight},
    {"weight_unit", :weight_unit},
    {"rate", :rate},
    {"rate_unit", :rate_unit},
    {"strength", :strength},
    {"strength_unit", :strength_unit},
    {"strength_per", :strength_per}
  ]

  @names Enum.map(@fields, &elem(&1, 0))

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Dose calculator", result: nil, problems: %{})
     |> assign_fields(start())}
  end

  # A new form: no number, and the first unit of each list.
  defp start do
    first = fn units -> hd(units).code end

    %{
      "weight" => "",
      "weight_unit" => first.(Dosage.weight_units()),
      "rate" => "",
      "rate_unit" => first.(Dosage.dose_units()),
      "strength" => "",
      "strength_unit" => first.(Dosage.strength_units()),
      "strength_per" => first.(Dosage.strength_per())
    }
  end

  defp assign_fields(socket, fields) do
    assign(socket,
      fields: fields,
      form: typed_form(fields, as: :dose),
      volume?: Dosage.volume?(fields["rate_unit"])
    )
  end

  # The fields that the browser sent, over the ones of the page. A form
  # with a dose rate in mL has no strength, so the browser sends none, and
  # the page keeps what the person typed there before.
  defp merged(socket, sent) do
    sent = sent |> typed_fields() |> Map.take(@names)

    socket.assigns.fields
    |> Map.merge(sent)
    |> Map.new(fn
      {name, value} when is_binary(value) -> {name, value}
      {name, _list} -> {name, ""}
    end)
  end

  @impl true
  def handle_event("change", %{"dose" => sent}, socket) when is_map(sent) do
    fields = merged(socket, sent)

    if fields == socket.assigns.fields do
      {:noreply, socket}
    else
      # What the page shows is for the fields as they are: a result of other
      # numbers goes, and so do the words about them.
      {:noreply, socket |> assign(result: nil, problems: %{}) |> assign_fields(fields)}
    end
  end

  def handle_event("calculate", %{"dose" => sent}, socket) when is_map(sent) do
    fields = merged(socket, sent)
    typed = Map.new(@fields, fn {name, key} -> {key, fields[name]} end)

    socket = assign_fields(socket, fields)

    with {:ok, given} <- Dosage.read(typed),
         {:ok, result} <- Dosage.calculate(given) do
      {:noreply, assign(socket, result: result, problems: %{})}
    else
      {:error, problems} ->
        {:noreply, assign(socket, result: nil, problems: in_words(problems))}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # The problems of each field, in words.
  defp in_words(problems) do
    Enum.group_by(problems, &elem(&1, 0), &ToolWords.problem/1)
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      section={:tools}
    >
      <nav aria-label="Breadcrumb">
        <.link navigate={~p"/o/#{@organisation.short_name}/tools"}>Tools</.link>
      </nav>

      <.header>
        Dose calculator
        <:subtitle>A body weight times a dose rate, with each step of the arithmetic.</:subtitle>
      </.header>

      <.vet_note />

      <.dose_form form={@form} problems={@problems} volume?={@volume?} />

      <.dose_result result={@result} />
    </Layouts.app>
    """
  end
end
