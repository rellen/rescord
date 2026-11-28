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

  A member can take the body weight from the journal of a resident: with a
  choice in the form, or from the page of a resident, which opens this one
  with `?resident=<id>`. The page reads the journal as the member. It fills
  in the weight when the journal has one measurement that can be a body
  weight, and asks which one when it has more. Below the field it says
  what it read and how old that is. A weight that the person then changes
  is a typed weight, and the page says so.

  A member can take the strength from an item of the inventory that has
  one: with a choice in the form, or from the page of the item, which
  opens this one with `?item=<id>`. The page says which item it read, and
  says when the records have no stock of it that is in date.

  The page reads only the fields that it knows from what the browser
  sends, and makes no atom from it.
  """

  use RescordWeb, :live_view

  import RescordWeb.ToolComponents

  alias Rescord.{Accounts, Dosage, Inventory, Journal, Residents}
  alias Rescord.Units.Quantity
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

  # The names of the form: the fields of the calculation, and the choices of
  # a resident and of an item.
  @names ["resident", "item" | Enum.map(@fields, &elem(&1, 0))]

  @weight_names ["weight", "weight_unit"]
  @strength_names ["strength", "strength_unit", "strength_per"]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, residents} = Residents.residents([load: [:name, :status]] ++ options(socket))

    {:ok,
     socket
     |> assign(
       page_title: "Dose calculator",
       result: nil,
       problems: %{},
       # The residents that are not gone, by name. A dose is for an animal
       # that is here or comes.
       residents:
         residents
         |> Enum.reject(&(&1.status == :left))
         |> Enum.map(&{&1.name || "A resident with no name", &1.id})
         |> Enum.sort(),
       resident: nil,
       weights: [],
       source: nil,
       items: items(socket),
       item: nil,
       from_item?: false
     )
     |> assign_fields(start())}
  end

  # The items of the inventory with a strength that the calculator takes,
  # by name, read as the member.
  defp items(socket) do
    case Inventory.items(options(socket)) do
      {:ok, items} ->
        for item <- Enum.sort_by(items, &{&1.name, &1.id}), Dosage.strength?(item.strength) do
          %{id: item.id, name: item.name, strength: item.strength}
        end

      {:error, _refused} ->
        []
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, socket |> choose_resident(params["resident"]) |> choose_item(params["item"])}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  # The resident of the address, when it is one of the list. Each other
  # value is no resident.
  defp choose_resident(socket, id) do
    resident =
      Enum.find_value(socket.assigns.residents, fn {name, known} ->
        known == id && %{id: known, name: name}
      end)

    if resident == socket.assigns.resident do
      socket
    else
      weights = if resident, do: weights(socket, resident), else: []

      socket
      |> assign(resident: resident, weights: weights)
      |> without_weight_of_a_record()
      |> then(
        &assign_fields(
          &1,
          Map.put(&1.assigns.fields, "resident", (resident && resident.id) || "")
        )
      )
      |> use_the_one_weight()
    end
  end

  # The newest measurement of each kind that can be a body weight, read as
  # the member. A member who cannot read the journal gets none.
  defp weights(socket, resident) do
    organisation = socket.assigns.organisation
    today = Accounts.today(organisation)

    case Journal.latest_measurements(resident.id, options(socket)) do
      {:ok, entries} ->
        for entry <- entries,
            {:ok, quantity} <- [Journal.quantity(entry.measurement)],
            Dosage.weight?(quantity) do
          on = Accounts.local_date(organisation, entry.happened_at)

          %{
            id: entry.measurement.measure_kind_id,
            resident: resident.name,
            kind: to_string(entry.measurement.measure_kind.label),
            quantity: quantity,
            on: on,
            days: Date.diff(today, on)
          }
        end

      {:error, _refused} ->
        []
    end
  end

  # A weight of the journal of one resident is not the weight of the next:
  # the field is empty again, and a result of it goes.
  defp without_weight_of_a_record(%{assigns: %{source: nil}} = socket), do: socket

  defp without_weight_of_a_record(socket) do
    socket
    |> assign(source: nil, result: nil, problems: %{})
    |> assign_fields(Map.put(socket.assigns.fields, "weight", ""))
  end

  # The item of the address, when it is one of the list. Each other value
  # is no item. The strength of the item goes into the form.
  defp choose_item(socket, id) do
    item = Enum.find(socket.assigns.items, &(&1.id == id))

    if (item && item.id) == (socket.assigns.item && socket.assigns.item.id) do
      socket
    else
      socket
      |> assign(item: item && Map.put(item, :in_date?, in_date?(socket, item)))
      |> without_strength_of_a_record()
      |> then(&assign_fields(&1, Map.put(&1.assigns.fields, "item", (item && item.id) || "")))
      |> use_strength()
    end
  end

  # Whether the records have stock of the item that is not past its expiry
  # date. The page says when there is none, and still calculates.
  defp in_date?(socket, item) do
    case Inventory.item_stock(item.id, options(socket)) do
      {:ok, %{lots: lots}} ->
        Enum.any?(lots, &(Decimal.positive?(&1.level) and &1.expiry != :expired))

      _none ->
        false
    end
  end

  # The strength of one item is not the strength of the next, or of no
  # item: the field is empty again, and a result of it goes.
  defp without_strength_of_a_record(%{assigns: %{from_item?: false}} = socket), do: socket

  defp without_strength_of_a_record(socket) do
    socket
    |> assign(from_item?: false, result: nil, problems: %{})
    |> assign_fields(Map.put(socket.assigns.fields, "strength", ""))
  end

  defp use_strength(%{assigns: %{item: nil}} = socket), do: socket

  defp use_strength(%{assigns: %{item: %{strength: strength}}} = socket) do
    fields =
      Map.merge(socket.assigns.fields, %{
        "strength" => Quantity.plain(strength),
        "strength_unit" => strength.unit.numerator.code,
        "strength_per" => strength.unit.denominator.code
      })

    socket
    |> assign(from_item?: true, result: nil, problems: %{})
    |> assign_fields(fields)
  end

  # One measurement that can be a body weight is the weight. With more, the
  # person says which one.
  defp use_the_one_weight(%{assigns: %{weights: [weight]}} = socket),
    do: use_weight(socket, weight)

  defp use_the_one_weight(socket), do: socket

  defp use_weight(socket, %{quantity: quantity} = weight) do
    fields =
      Map.merge(socket.assigns.fields, %{
        "weight" => Quantity.plain(quantity),
        "weight_unit" => quantity.unit.code
      })

    socket
    |> assign(source: weight, result: nil, problems: %{})
    |> assign_fields(fields)
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
      "strength_per" => first.(Dosage.strength_per()),
      "resident" => "",
      "item" => ""
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
    sent = sent |> text_fields() |> Map.take(@names)

    socket.assigns.fields
    |> Map.merge(sent)
    |> Map.new(fn
      {name, value} when is_binary(value) -> {name, value}
      {name, _list} -> {name, ""}
    end)
  end

  # Takes what the browser sent into the page. What the page shows is for
  # the fields as they are: after a change, a result of other numbers goes,
  # and so do the words about them. A weight that the person changed is no
  # more the weight of the journal, and a strength that the person changed
  # is no more the strength of the item.
  defp take(socket, sent) do
    before = socket.assigns.fields
    fields = merged(socket, sent)
    same? = fn names -> Map.take(fields, names) == Map.take(before, names) end

    if fields == before do
      socket
    else
      socket
      |> assign(
        result: nil,
        problems: %{},
        source: if(same?.(@weight_names), do: socket.assigns.source),
        from_item?: socket.assigns.from_item? and same?.(@strength_names)
      )
      |> assign_fields(fields)
    end
  end

  # The address of the page with the resident and the item that the form
  # names. The page of that address reads the weights and the strength
  # (`handle_params/3`).
  defp follow_choices(socket) do
    %{fields: fields, resident: resident, item: item} = socket.assigns

    if fields["resident"] == ((resident && resident.id) || "") and
         fields["item"] == ((item && item.id) || "") do
      socket
    else
      push_patch(socket, to: address(socket.assigns.organisation, fields))
    end
  end

  defp address(organisation, fields) do
    case for {key, name} <- [resident: "resident", item: "item"],
             fields[name] != "",
             do: {key, fields[name]} do
      [] -> ~p"/o/#{organisation.short_name}/tools/dose"
      choices -> ~p"/o/#{organisation.short_name}/tools/dose?#{choices}"
    end
  end

  @impl true
  def handle_event("change", %{"dose" => sent}, socket) when is_map(sent) do
    {:noreply, socket |> take(sent) |> follow_choices()}
  end

  # The person chose one of the weights of the journal. The page finds it
  # among the ones that it read, and takes no number from the browser.
  def handle_event("use_weight", %{"kind" => kind}, socket) do
    case Enum.find(socket.assigns.weights, &(&1.id == kind)) do
      nil -> {:noreply, socket}
      weight -> {:noreply, use_weight(socket, weight)}
    end
  end

  def handle_event("calculate", %{"dose" => sent}, socket) when is_map(sent) do
    socket = take(socket, sent)
    fields = socket.assigns.fields
    typed = Map.new(@fields, fn {name, key} -> {key, fields[name]} end)

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
      inbox={@inbox}
      ruby={@ruby?}
      section={:tools}
    >
      <nav aria-label="Breadcrumb">
        <.link navigate={~p"/o/#{@organisation.short_name}/tools"}>Tools</.link>
      </nav>

      <.header icon={Icons.section(:dose)}>
        Dose calculator
        <:subtitle>A body weight times a dose rate, with each step of the arithmetic.</:subtitle>
      </.header>

      <.vet_note />

      <.dose_form
        form={@form}
        problems={@problems}
        volume?={@volume?}
        residents={@residents}
        resident={@resident}
        weights={@weights}
        source={@source}
        items={@items}
        item={@item}
        from_item?={@from_item?}
      />

      <.dose_result
        result={@result}
        resident={@resident}
        source={@source}
        item={@item}
        from_item?={@from_item?}
      />
    </Layouts.app>
    """
  end
end
