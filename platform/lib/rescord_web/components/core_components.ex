defmodule RescordWeb.CoreComponents do
  @moduledoc """
  The core UI components: flash messages, buttons, form inputs, the page
  header, tables and data lists. The icons are in `RescordWeb.Icons`.

  The markup is semantic and classless (ADR 0004). The stylesheet under
  `assets/css/` styles the elements, their ARIA states and a few `data-`
  attributes, so a component sets no class. A variant that no element or
  ARIA state expresses is a `data-` attribute, such as
  `data-variant="primary"` on a button.

  The components keep the attributes and slots of the components that
  `mix phx.new` generates, so the output of `phx.gen.*` and of the Ash
  generators still calls them. That output still has Tailwind classes and
  Heroicon names, and must be restyled by hand.
  """
  use Phoenix.Component
  use Gettext, backend: RescordWeb.Gettext

  import RescordWeb.Icons, only: [icon: 1]

  alias Phoenix.LiveView.JS

  @doc """
  Renders a flash message.

  An error is an alert; an information is a status. A click on the message
  closes it.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash id="welcome-back" kind={:info}>Welcome back!</.flash>
  """
  attr :id, :string, doc: "the optional id of the flash message"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash message"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      role={if @kind == :error, do: "alert", else: "status"}
      data-flash={@kind}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      {@rest}
    >
      <.icon :if={@kind == :info} name="information-circle" />
      <.icon :if={@kind == :error} name="exclamation-circle" />
      <p>
        <strong :if={@title}>{@title}</strong>
        {msg}
      </p>
      <button type="button" aria-label={gettext("close")}>
        <.icon name="x-mark" />
      </button>
    </div>
    """
  end

  @doc """
  Renders a button, or a link that looks like a button.

  A button is quiet unless `variant` is `"primary"` or it submits a form.
  A link gets `data-variant`, which the stylesheet uses to draw it as a
  button.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled type form)

  attr :variant, :string,
    default: nil,
    values: [nil, "primary", "danger"],
    doc: "`danger` is the last button of a `confirm/1`, and only that"

  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link data-variant={@variant || "secondary"} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button data-variant={@variant} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders a form control with its label and its errors.

  A `Phoenix.HTML.FormField` may be passed as argument, which is used to
  retrieve the input name, id, and values. Otherwise all attributes may be
  passed explicitly.

  A control with errors gets `aria-invalid="true"` and an
  `aria-describedby` that names the `<small>` element with its errors.
  `hint` gives a text control or a select words below it, which say what
  it takes, and the control names them too.

  A control of the type `number` gets an `inputmode`, so a phone shows its
  keyboard of digits (ADR 0061).

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * `type="decimal"` is a number with a part, such as a weight or a
      quantity: a text field with the keyboard of a phone for a decimal
      (ADR 0111). A field of `type="number"` drops a comma that a person
      types, so "1,2" became 12, and an arrow key changed the number.

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://phoenix-html.hexdocs.pm/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local decimal email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []

  attr :hint, :string,
    default: nil,
    doc: "words below the control, which say what it takes. The control names them too"

  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include: ~w(accept autocapitalize autocomplete capture cols disabled enterkeyhint form
                inputmode list max maxlength min minlength multiple pattern placeholder readonly
                required rows size spellcheck step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div>
      <label for={@id}>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          aria-invalid={@errors != [] && "true"}
          aria-describedby={described_by(@id, @errors, @hint)}
          {@rest}
        />
        {@label}
      </label>
      <.errors id={@id} errors={@errors} />
      <.hint id={@id} hint={@hint} />
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div>
      <label :if={@label} for={@id}>{@label}</label>
      <select
        id={@id}
        name={@name}
        multiple={@multiple}
        aria-invalid={@errors != [] && "true"}
        aria-describedby={described_by(@id, @errors, @hint)}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.errors id={@id} errors={@errors} />
      <.hint id={@id} hint={@hint} />
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <label :if={@label} for={@id}>{@label}</label>
      <textarea
        id={@id}
        name={@name}
        aria-invalid={@errors != [] && "true"}
        aria-describedby={described_by(@id, @errors, @hint)}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.errors id={@id} errors={@errors} />
      <.hint id={@id} hint={@hint} />
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    assigns =
      assigns
      |> assign(:rest, keyboard(assigns.type, assigns.rest))
      |> assign(:type, if(assigns.type == "decimal", do: "text", else: assigns.type))

    ~H"""
    <div>
      <label :if={@label} for={@id}>{@label}</label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        aria-invalid={@errors != [] && "true"}
        aria-describedby={described_by(@id, @errors, @hint)}
        {@rest}
      />
      <.errors id={@id} errors={@errors} />
      <.hint id={@id} hint={@hint} />
    </div>
    """
  end

  # The keyboard of a phone for a number (ADR 0061): the digits alone for a
  # whole number, and the digits with a decimal mark where the step allows a
  # part of a number. A page that states an `inputmode` keeps it.
  defp keyboard("number", rest) do
    mode = if rest[:step] in [nil, "1", 1], do: "numeric", else: "decimal"
    Map.put_new(rest, :inputmode, mode)
  end

  # A decimal is text that the browser does not change: no arrow key, no
  # spelling, and no list of what was typed before (ADR 0111). A page that
  # states one of these keeps it. A step and a limit are for a number field
  # only: the action checks the limits.
  defp keyboard("decimal", rest) do
    rest
    |> Map.drop([:step, :min, :max])
    |> Map.put_new(:inputmode, "decimal")
    |> Map.put_new(:autocomplete, "off")
    |> Map.put_new(:spellcheck, "false")
  end

  defp keyboard(_type, rest), do: rest

  defp error_id(id), do: "#{id}-error"
  defp hint_id(id), do: "#{id}-hint"

  # The ids of what describes a control: its errors, then its hint.
  defp described_by(id, errors, hint) do
    case [errors != [] && error_id(id), hint && hint_id(id)] |> Enum.filter(& &1) do
      [] -> false
      ids -> Enum.join(ids, " ")
    end
  end

  # The errors of a form control, which the control names in its
  # aria-describedby.
  attr :id, :any, required: true
  attr :errors, :list, required: true

  defp errors(assigns) do
    ~H"""
    <small :if={@errors != []} id={error_id(@id)}>
      <.icon name="exclamation-circle" />
      <span :for={msg <- @errors}>{msg}</span>
    </small>
    """
  end

  # The hint of a form control, which the control names in its
  # aria-describedby. `data-hint` keeps the look of an error from it.
  attr :id, :any, required: true
  attr :hint, :string, required: true

  defp hint(assigns) do
    ~H"""
    <small :if={@hint} id={hint_id(@id)} data-hint>{@hint}</small>
    """
  end

  @doc """
  Renders the header of a page: its breadcrumb, its title, an optional
  subtitle and optional actions.

  A page below a page of the site menu names the way up to that page in
  `crumb` slots, the highest first (issue 35). The breadcrumb is a `nav`
  before the header, and the stylesheet draws the separator. A "back"
  button does not go in `actions`: the breadcrumb is the way back.

  ## Examples

      <.header icon={Icons.section(:journal)}>
        <:crumb navigate={~p"/o/wattle/residents"}>Residents</:crumb>
        <:crumb navigate={~p"/o/wattle/residents/\#{id}"}>Clover</:crumb>
        Journal of Clover
      </.header>
  """
  attr :icon, :string,
    default: nil,
    doc: "the shape of the part of the site that the page is (`RescordWeb.Icons.section/1`)"

  slot :crumb, doc: "a page above this one, the highest first" do
    attr :navigate, :string, doc: "the address of that page, for a live navigation"
    attr :patch, :string, doc: "the address of that page, for a patch of the same LiveView"
  end

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <nav :if={@crumb != []} aria-label="Breadcrumb">
      <ol>
        <li :for={crumb <- @crumb}>
          <.link navigate={crumb[:navigate]} patch={crumb[:patch]}>{render_slot(crumb)}</.link>
        </li>
      </ol>
    </nav>
    <header>
      <hgroup>
        <h1><.icon :if={@icon} name={@icon} /> {render_slot(@inner_block)}</h1>
        <p :if={@subtitle != []}>{render_slot(@subtitle)}</p>
      </hgroup>
      <div :if={@actions != []}>{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table, with a header cell of scope `col` for each column.

  On a phone each row is a card (ADR 0061): the first cell is its title, and
  each other cell says its column with `data-label`.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :caption, doc: "the optional caption of the table"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table>
      <caption :if={@caption != []}>{render_slot(@caption)}</caption>
      <thead>
        <tr>
          <th :for={col <- @col} scope="col">{col[:label]}</th>
          <th :if={@action != []} scope="col">{gettext("Actions")}</th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={{col, index} <- Enum.with_index(@col)}
            data-label={index > 0 && col[:label]}
            phx-click={@row_click && @row_click.(row)}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []}>
            <%= for action <- @action do %>
              {render_slot(action, @row_item.(row))}
            <% end %>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a description list of titles and values.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <dl>
      <div :for={item <- @item}>
        <dt>{item.title}</dt>
        <dd>{render_slot(item)}</dd>
      </div>
    </dl>
    """
  end

  @doc """
  Renders a state as a shape and a word, never as a colour alone.

  `ok` is well and done, `alert` is what needs somebody now, `info` is
  information and what is coming, and `none` is no state yet. The stylesheet
  gives each its colour (ADR 0015).

  ## Examples

      <.state kind="ok">In care</.state>
      <.state kind="alert">Medication due</.state>
  """
  attr :kind, :string, required: true, values: ~w(ok alert info none)
  attr :rest, :global
  slot :inner_block, required: true

  def state(assigns) do
    ~H"""
    <span data-state={@kind} {@rest}>
      <.icon :if={@kind != "none"} name={state_icon(@kind)} />{render_slot(@inner_block)}
    </span>
    """
  end

  defp state_icon("ok"), do: "check"
  defp state_icon("alert"), do: "exclamation-triangle"
  defp state_icon("info"), do: "clock"

  @doc """
  Says what an action refused, each problem in a paragraph with the role
  `alert`. A page draws it below its header, or in the form that the person
  sent when that form is far down the page. This is the one way a page says
  that an action was refused (issue 35): a page writes no `role="alert"`
  of its own.

  A page with several forms keeps, beside the problems, the name of the
  form that was sent (`at`), and draws `<.problems>` in each form with the
  name of that form (`here`). Only the form that was sent shows them.

      <.problems list={@problems} />
      <.problems list={@problems} at={@problems_at} here={:family} />
  """
  attr :list, :list, required: true, doc: "the problems, each in words for a person"
  attr :at, :any, default: nil, doc: "the name of the form that was sent"
  attr :here, :any, default: nil, doc: "the name of the form that this draws in"

  def problems(assigns) do
    ~H"""
    <p :for={problem <- if(@at == @here, do: @list, else: [])} role="alert">
      <.icon name="exclamation-circle" /> {problem}
    </p>
    """
  end

  @doc """
  The one step that a person takes before an action that removes, ends,
  withdraws, revokes, retires or forgets a thing (issue 35).

  A `<details>`: its summary says the action, its body says what happens,
  and its last control is `<.button variant="danger">` with the same verb
  and the name of the thing. A form inside it (a reason, a date) keeps its
  fields. The browser dialog of `data-confirm` is not used: it has none of
  our look, and a page test does not see it.

  ## Examples

      <.confirm id="remove-item" summary="Remove the item">
        <p>The item leaves the inventory. Its history stays.</p>
        <.button variant="danger" phx-click="remove">Remove Meadow hay</.button>
      </.confirm>
  """
  attr :id, :string, required: true
  attr :summary, :string, required: true, doc: "the action, as the summary shows it"

  attr :label, :string,
    default: nil,
    doc: "the name of the summary where many are on a page; it starts with `summary`"

  attr :icon, :string, default: "trash", doc: "the shape of the action, or nil"
  attr :rest, :global
  slot :inner_block, required: true

  def confirm(assigns) do
    ~H"""
    <details id={@id} data-confirm-step {@rest}>
      <summary aria-label={@label}><.icon :if={@icon} name={@icon} /> {@summary}</summary>
      {render_slot(@inner_block)}
    </details>
    """
  end

  ## JS Commands

  @doc "Shows the element that `selector` names."
  def show(js \\ %JS{}, selector), do: JS.show(js, to: selector)

  @doc "Hides the element that `selector` names."
  def hide(js \\ %JS{}, selector), do: JS.hide(js, to: selector)

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(RescordWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(RescordWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
