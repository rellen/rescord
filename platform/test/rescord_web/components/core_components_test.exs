defmodule RescordWeb.CoreComponentsTest do
  # The markup contract of the core components (ADR 0004): no class
  # attribute, and the ARIA states that the stylesheet reads.
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import RescordWeb.CoreComponents

  defp parse(html), do: LazyHTML.from_fragment(html)

  defp attribute(doc, selector, name),
    do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  test "a control with errors is invalid and described by its errors" do
    doc =
      render_component(&input/1,
        id: "title",
        name: "title",
        label: "Title",
        value: "",
        errors: ["can't be blank"]
      )
      |> parse()

    assert attribute(doc, "input#title", "aria-invalid") == ["true"]
    assert attribute(doc, "input#title", "aria-describedby") == ["title-error"]
    assert doc |> LazyHTML.query("small#title-error") |> LazyHTML.text() =~ "can't be blank"
    assert attribute(doc, "label", "for") == ["title"]
  end

  test "a control without errors is neither invalid nor described" do
    doc =
      render_component(&input/1, id: "title", name: "title", label: "Title", value: "") |> parse()

    assert attribute(doc, "input#title", "aria-invalid") == []
    assert attribute(doc, "input#title", "aria-describedby") == []
    assert doc |> LazyHTML.query("small") |> Enum.count() == 0
  end

  test "a checkbox with errors is invalid inside its label" do
    doc =
      render_component(&input/1,
        type: "checkbox",
        id: "done",
        name: "done",
        label: "Done",
        errors: ["is invalid"]
      )
      |> parse()

    assert attribute(doc, ~s(label > input[type="checkbox"]), "aria-invalid") == ["true"]

    assert attribute(doc, ~s(label > input[type="checkbox"]), "aria-describedby") == [
             "done-error"
           ]
  end

  test "a primary button and a link button carry their variant" do
    assigns = %{}

    doc =
      rendered_to_string(~H"""
      <.button variant="primary">Save</.button>
      <.button>Quiet</.button>
      <.button navigate="/">Home</.button>
      """)
      |> parse()

    assert attribute(doc, "button", "data-variant") == ["primary"]
    assert attribute(doc, "a", "data-variant") == ["secondary"]
  end

  test "an error flash is an alert and an information flash is a status" do
    flash = %{"info" => "Saved.", "error" => "Not saved."}

    info = render_component(&flash/1, kind: :info, flash: flash) |> parse()
    error = render_component(&flash/1, kind: :error, flash: flash) |> parse()

    assert attribute(info, "[data-flash]", "role") == ["status"]
    assert attribute(error, "[data-flash]", "role") == ["alert"]
    assert attribute(error, "button", "aria-label") == ["close"]
  end

  test "a state is a shape and a word" do
    for {kind, icons} <- [{"ok", 1}, {"alert", 1}, {"info", 1}, {"none", 0}] do
      assigns = %{kind: kind}

      doc =
        rendered_to_string(~H"""
        <.state kind={@kind}>In care</.state>
        """)
        |> parse()

      assert doc |> LazyHTML.query(~s(span[data-state="#{kind}"])) |> LazyHTML.text() =~ "In care"

      assert doc |> LazyHTML.query(~s(span[data-state] > svg[aria-hidden="true"])) |> Enum.count() ==
               icons
    end
  end

  test "an icon is hidden from assistive technology" do
    doc = render_component(&icon/1, name: "x-mark") |> parse()

    assert attribute(doc, "svg", "aria-hidden") == ["true"]
    assert attribute(doc, "svg", "focusable") == ["false"]
  end

  test "no component renders a class attribute" do
    assigns = %{rows: [%{id: 1, name: "One"}]}

    doc =
      rendered_to_string(~H"""
      <.header>
        Title
        <:subtitle>Subtitle</:subtitle>
        <:actions><.button>Act</.button></:actions>
      </.header>
      <.table id="rows" rows={@rows}>
        <:col :let={row} label="Name">{row.name}</:col>
        <:action :let={row}><.link navigate={"/#{row.id}"}>Show</.link></:action>
      </.table>
      <.list>
        <:item title="Name">One</:item>
      </.list>
      <.input name="body" type="textarea" label="Body" value="" errors={["is too short"]} />
      <.input name="kind" type="select" label="Kind" options={["A", "B"]} value="A" />
      <.flash kind={:info} flash={%{"info" => "Saved."}} />
      <.icon name="arrow-path" spin />
      """)
      |> parse()

    assert doc |> LazyHTML.query("[class]") |> Enum.count() == 0
    assert doc |> LazyHTML.query(~s(th[scope="col"])) |> Enum.count() == 2
    assert doc |> LazyHTML.query("dl > div > dt + dd") |> Enum.count() == 1
  end
end
