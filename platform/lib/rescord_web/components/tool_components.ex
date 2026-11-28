defmodule RescordWeb.ToolComponents do
  @moduledoc """
  The parts of the pages of the tools (ADR 0072 and ADR 0037): the list of
  the tools, and the note, the form and the result of the dose calculator.

  Each part is a function component. The state of the calculator is one
  form and one result, and `RescordWeb.DoseLive` holds both.
  """

  use RescordWeb, :html

  alias Rescord.Dosage
  alias RescordWeb.ToolWords

  @doc """
  The tools of an organisation: a card for each, with its name, which is
  the link, and a line that says what it does.
  """
  attr :organisation, :map, required: true

  def tools(assigns) do
    ~H"""
    <ul data-tools>
      <li>
        <a href={~p"/o/#{@organisation.short_name}/tools/dose"}>Dose calculator</a>
        <small>
          A body weight times a dose rate, as a dose, a volume or a number of tablets, with
          each step of the arithmetic.
        </small>
      </li>
    </ul>
    """
  end

  @doc """
  The note that the dose calculator shows at all times: what the page does
  and does not know, and that a vet checks the result. Nothing closes it.
  """
  def vet_note(assigns) do
    ~H"""
    <aside id="vet-note" aria-labelledby="vet-note-heading">
      <h2 id="vet-note-heading">
        <.icon name="exclamation-triangle" /> Check with your vet
      </h2>
      <p>
        This page does arithmetic and nothing more. It does not know the medication, the
        species or the animal, and it cannot say that a dose is safe.
      </p>
      <p>
        Take the dose rate and the strength from your vet or from the label. Check the
        result with your vet before you give it.
      </p>
    </aside>
    """
  end

  @doc """
  The form of the dose calculator: the body weight, the dose rate, and the
  strength of the product, each a number with its unit.

  A number is a text field with the decimal keyboard of a phone, and not a
  field of the type `number`: such a field changes its value under the
  wheel of a mouse, and takes `1e3`. A unit is a choice from a list. A dose
  rate in mL gives a volume, so the form then has no strength.

  The body weight can come from the journal of a resident. The form then
  lists the measurements that can be a body weight when there is more than
  one, and says below the field which one it holds and how old it is.
  """
  attr :form, Phoenix.HTML.Form, required: true
  attr :problems, :map, required: true, doc: "the problems of each field, in words"
  attr :volume?, :boolean, required: true, doc: "the dose rate gives a volume"
  attr :residents, :list, default: [], doc: "the residents of the choice, each with its id"
  attr :resident, :map, default: nil, doc: "the resident that the person chose"
  attr :weights, :list, default: [], doc: "the measurements of that resident that fit"
  attr :source, :map, default: nil, doc: "the measurement that the weight came from"

  def dose_form(assigns) do
    assigns =
      assign(assigns,
        weight_units: options(Dosage.weight_units()),
        dose_units: options(Dosage.dose_units()),
        strength_units: options(Dosage.strength_units()),
        strength_per: options(Dosage.strength_per())
      )

    ~H"""
    <.form for={@form} id="dose" phx-change="change" phx-submit="calculate" novalidate>
      <fieldset>
        <legend>Body weight</legend>
        <.input
          :if={@residents != []}
          field={@form[:resident]}
          type="select"
          label="From the journal of a resident (optional)"
          prompt="No resident"
          options={@residents}
        />
        <p :if={@resident && @weights == []} id="dose-no-weight">
          The journal of {@resident.name} has no weight in kg, g, lb or oz that you can read.
          Type the body weight.
        </p>
        <div :if={match?([_, _ | _], @weights)} id="dose-weights">
          <p>
            The journal of {@resident.name} has more than one measurement that can be a body weight.
          </p>
          <ul data-weights>
            <li :for={weight <- @weights}>
              <span>{ToolWords.measurement(weight)}</span>
              <button
                type="button"
                data-variant="secondary"
                phx-click="use_weight"
                phx-value-kind={weight.id}
                aria-pressed={to_string(@source != nil and @source.id == weight.id)}
              >
                Use this weight
              </button>
            </li>
          </ul>
        </div>
        <div data-quantity>
          <.number
            field={@form[:weight]}
            label="Weight"
            errors={@problems[:weight]}
            hint={@source && ToolWords.source(@source)}
          />
          <.input
            field={@form[:weight_unit]}
            type="select"
            label="Unit"
            aria-label="Unit of the body weight"
            options={@weight_units}
          />
        </div>
      </fieldset>

      <fieldset>
        <legend>Dose rate, for each kg</legend>
        <div data-quantity>
          <.number
            field={@form[:rate]}
            label="Dose"
            errors={@problems[:rate]}
            hint="From your vet or from the label, for each kg of body weight."
          />
          <.input
            field={@form[:rate_unit]}
            type="select"
            label="Unit"
            aria-label="Unit of the dose rate"
            options={@dose_units}
          />
        </div>
      </fieldset>

      <fieldset :if={!@volume?} id="dose-strength-part">
        <legend>Strength of the product</legend>
        <div data-quantity>
          <.number
            field={@form[:strength]}
            label="Amount"
            errors={@problems[:strength]}
            hint="From the label. Leave it empty for the dose alone."
          />
          <.input
            field={@form[:strength_unit]}
            type="select"
            label="Unit"
            aria-label="Unit of the strength"
            options={@strength_units}
          />
          <.input
            field={@form[:strength_per]}
            type="select"
            label="In each"
            aria-label="The strength is in each"
            options={@strength_per}
          />
        </div>
      </fieldset>

      <p :if={@volume?} id="dose-no-strength">
        A dose rate in mL gives a volume, so the strength has no part in it.
      </p>

      <.problems list={@problems[:calculation] || []} />
      <p :if={refused?(@problems)} role="alert">
        There is no result yet. See the words below each marked field.
      </p>

      <button type="submit">Calculate</button>
    </.form>
    """
  end

  defp refused?(problems), do: Enum.any?([:weight, :rate, :strength], &Map.has_key?(problems, &1))

  defp options(units), do: Enum.map(units, &{&1.symbol, &1.code})

  # A number of the calculator: a text field with the decimal keyboard, its
  # hint, and the words of what the calculator refused.
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :errors, :list, default: nil
  attr :hint, :string, default: nil

  defp number(assigns) do
    assigns = assign(assigns, errors: assigns.errors || [])

    ~H"""
    <div>
      <label for={@field.id}>{@label}</label>
      <input
        type="text"
        inputmode="decimal"
        autocomplete="off"
        autocapitalize="none"
        spellcheck="false"
        maxlength="16"
        id={@field.id}
        name={@field.name}
        value={@field.value}
        aria-invalid={@errors != [] && "true"}
        aria-describedby={describedby(@field.id, @hint, @errors)}
      />
      <small :if={@errors != []} id={"#{@field.id}-error"}>
        <.icon name="exclamation-circle" />
        <span :for={words <- @errors}>{words}</span>
      </small>
      <small :if={@hint && @errors == []} id={"#{@field.id}-hint"}>{@hint}</small>
    </div>
    """
  end

  defp describedby(id, _hint, [_ | _]), do: "#{id}-error"
  defp describedby(id, hint, []) when is_binary(hint), do: "#{id}-hint"
  defp describedby(_id, _hint, _errors), do: nil

  @doc """
  The result of the dose calculator: the amount to measure, what went in,
  each step of the working, and the note to check it with a vet.

  The answer is an `output` of the form. It is in the page before there is
  a result, with words that say so: a screen reader says what comes into
  an element that it knows, and not always what comes with a new one. The
  number takes the focus when it comes, which brings it into view on a
  phone, where the result is below the form. A number that was rounded has
  the word "about" before it.
  """
  attr :result, Dosage.Result, default: nil
  attr :resident, :map, default: nil, doc: "the resident that the person chose"
  attr :source, :map, default: nil, doc: "the measurement that the weight came from"

  def dose_result(assigns) do
    ~H"""
    <section id="dose-result" aria-labelledby="dose-result-heading">
      <h2 id="dose-result-heading">Result</h2>

      <output id="dose-answer" form="dose" for="dose_weight dose_rate dose_strength">
        <span :if={!@result}>No result yet. Press Calculate.</span>
        <strong :if={@result} id="dose-amount" tabindex="-1" phx-mounted={JS.focus()}>
          {ToolWords.worked(@result.amount || @result.dose)}
        </strong>
        <span :if={@result && @result.amount}>
          of the product, which holds a dose of {ToolWords.worked(@result.dose)}
        </span>
        <span :if={@result && !@result.amount}>is the dose</span>
      </output>

      <.dose_working :if={@result} result={@result} resident={@resident} source={@source} />
    </section>
    """
  end

  # What a result says below its answer: a result that is too small to
  # measure, what went in, the steps, and the note to check it with a vet.
  attr :result, Dosage.Result, required: true
  attr :resident, :map, default: nil
  attr :source, :map, default: nil

  defp dose_working(assigns) do
    ~H"""
    <p :for={note <- @result.notes} data-note>
      <.state kind="alert">Too small to measure</.state>
      {ToolWords.note(note)}
    </p>

    <h3>What went in</h3>
    <.list>
      <:item title="Body weight">
        {ToolWords.quantity(@result.weight)}
        <small :if={@source} id="dose-weight-from">{ToolWords.source(@source)}</small>
        <small :if={@resident && !@source} id="dose-weight-from">
          Typed, and not from the journal of {@resident.name}.
        </small>
      </:item>
      <:item title="Dose rate">{ToolWords.rate(@result.rate)}</:item>
      <:item :if={@result.strength} title="Strength">
        {ToolWords.strength(@result.strength)}
      </:item>
    </.list>

    <h3 id="dose-working-heading">The working</h3>
    <ol aria-labelledby="dose-working-heading" data-working>
      <li :for={step <- @result.steps}>{ToolWords.step(step)}</li>
    </ol>

    <p>
      <strong>Check this result with your vet before you give it.</strong>
      The page does not round the result to what a syringe or a tablet can give: your vet
      decides how to round it.
    </p>
    """
  end
end
