defmodule RescordWeb.ListComponents do
  @moduledoc """
  The parts of the pages of the lists of values (ADR 0016, ADR 0025 and
  ADR 0037): a list with its values, and the forms that add a value.
  """

  use RescordWeb, :html

  @doc "One value of a list, with the button that retires it or restores it."
  attr :value, :any, required: true
  attr :can_change?, :any, required: true
  attr :shared?, :any, required: true
  attr :list, :any, required: true

  def list_value(assigns) do
    ~H"""
    <li>
      {@value.label}
      <small :if={@value.origin}>({@value.origin}{if @value.retired?, do: ", retired"})</small>
      <.button
        :if={@can_change? and not @shared? and not @value.retired?}
        phx-click="retire"
        phx-value-dimension={@list.key}
        phx-value-id={@value.id}
        aria-label={"Retire #{@value.label} from #{String.downcase(@list.name)}"}
      >
        Retire
      </.button>
      <.button
        :if={@can_change? and not @shared? and @value.retired?}
        phx-click="restore"
        phx-value-dimension={@list.key}
        phx-value-id={@value.id}
        aria-label={"Restore #{@value.label} to #{String.downcase(@list.name)}"}
      >
        Restore
      </.button>
      <.value_units
        :if={@list.key == :measure_kind and not @shared?}
        value={@value}
        list={@list}
        can_change?={@can_change?}
      />
      <.value_soon_days
        :if={@list.key == :item_category and not @shared?}
        value={@value}
        can_change?={@can_change?}
      />
    </li>
    """
  end

  @doc """
  The units of a measure kind, and the form that changes them. A kind with
  no unit accepts each unit.
  """
  attr :value, :map, required: true
  attr :list, :map, required: true
  attr :can_change?, :boolean, required: true

  def value_units(assigns) do
    assigns = assign(assigns, names: unit_names(assigns.value.unit_ids, assigns.list.units))

    ~H"""
    <small>Units: {if @names == [], do: "any unit", else: Enum.join(@names, ", ")}</small>
    <details :if={@can_change? and @list.units != []} id={"units-details-#{@value.id}"}>
      <summary>Units of {@value.label}</summary>
      <form id={"units-#{@value.id}"} phx-submit="set_units">
        <input type="hidden" name="value_id" value={@value.id} />
        <fieldset>
          <legend>The units that a measurement of {@value.label} can have</legend>
          <label :for={{name, id} <- @list.units}>
            <input type="checkbox" name="units[ids][]" value={id} checked={id in @value.unit_ids} />
            {name}
          </label>
        </fieldset>
        <.button type="submit">Save the units of {@value.label}</.button>
      </form>
    </details>
    """
  end

  @doc """
  The days before its expiry date in which a lot of an item category
  expires soon, and the form that changes them.
  """
  attr :value, :map, required: true
  attr :can_change?, :boolean, required: true

  def value_soon_days(assigns) do
    ~H"""
    <small>
      Expires soon: {if @value.soon_days, do: "#{@value.soon_days} days", else: "30 days, the default"} before its date
    </small>
    <details :if={@can_change?} id={"soon-details-#{@value.id}"}>
      <summary>Days before expiry of {@value.label}</summary>
      <form id={"soon-#{@value.id}"} phx-submit="set_soon_days">
        <input type="hidden" name="value_id" value={@value.id} />
        <.input
          id={"soon-#{@value.id}-days"}
          name="soon[days]"
          type="number"
          label={"Days before its expiry date in which a lot of #{@value.label} expires soon. No number: 30"}
          min="0"
          max="3650"
          value={@value.soon_days}
        />
        <.button type="submit">Save the days of {@value.label}</.button>
      </form>
    </details>
    """
  end

  # The names of the units of a kind, in the order of the list of units.
  defp unit_names(ids, units), do: for({name, id} <- units, id in ids, do: name)

  @doc "The forms that add a value to a list: a shared value, or a value of its own."
  attr :list, :any, required: true
  attr :shared?, :any, required: true

  def add_value(assigns) do
    ~H"""
    <details id={"add-details-#{@list.key}"}>
      <summary>Add a value to {String.downcase(@list.name)}</summary>
      <form :if={@list.unused != []} id={"use-#{@list.key}"} phx-submit="use">
        <input type="hidden" name="dimension" value={@list.key} />
        <.input
          id={"use-#{@list.key}-value"}
          name="value[base_id]"
          type="select"
          label={"A shared value for #{String.downcase(@list.name)}"}
          options={@list.unused}
          value=""
        />
        <.button
          type="submit"
          aria-label={"Add the shared value to #{String.downcase(@list.name)}"}
        >
          Add the shared value
        </.button>
      </form>

      <form id={"add-#{@list.key}"} phx-submit="add">
        <input type="hidden" name="dimension" value={@list.key} />
        <.input
          id={"add-#{@list.key}-name"}
          name="value[name]"
          type="text"
          label={
            if @shared?,
              do: "A new shared value for #{String.downcase(@list.name)}",
              else: "A new local value for #{String.downcase(@list.name)}"
          }
          value=""
          maxlength="60"
          required
        />
        <.button type="submit" aria-label={"Add the value to #{String.downcase(@list.name)}"}>
          Add the value
        </.button>
      </form>
    </details>
    """
  end

  @doc "One list of values."
  attr :list, :any, required: true
  attr :can_change?, :any, required: true
  attr :shared?, :any, required: true

  def value_list(assigns) do
    ~H"""
    <section aria-labelledby={"list-#{@list.key}"}>
      <h2 id={"list-#{@list.key}"}>{@list.name}</h2>

      <p :if={@list.values == []}>The list is empty.</p>
      <ul :if={@list.values != []}>
        <.list_value
          :for={value <- @list.values}
          value={value}
          can_change?={@can_change?}
          shared?={@shared?}
          list={@list}
        />
      </ul>

      <.add_value :if={@can_change?} list={@list} shared?={@shared?} />
    </section>
    """
  end
end
