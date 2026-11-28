defmodule RescordWeb.ToolPagesTest do
  @moduledoc """
  Holds the pages of the tools (ADR 0072): the part Tools of the site menu,
  the list of the tools, and the dose calculator with its note, its
  result, its working and its guards.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    home = ~p"/o/#{organisation.short_name}"

    {:ok,
     organisation: organisation,
     member: member,
     home: home,
     tools: "#{home}/tools",
     dose: "#{home}/tools/dose"}
  end

  defp open(context, path) do
    {:ok, view, _html} = live(sign_in(build_conn(), context.member), path)
    view
  end

  # The fields of the form as the browser sends them.
  defp fields(changes) do
    Map.merge(
      %{
        "weight" => "",
        "weight_unit" => "kg",
        "rate" => "",
        "rate_unit" => "mg",
        "strength" => "",
        "strength_unit" => "mg",
        "strength_per" => "mL"
      },
      changes
    )
  end

  defp calculate(view, changes) do
    view |> form("#dose", dose: fields(changes)) |> render_submit()
  end

  describe "the tools of an organisation" do
    test "are a part of the site menu, which the page marks", context do
      view = open(context, context.tools)

      assert has_element?(view, "h1", "Tools")

      assert has_element?(
               view,
               ~s(#site-menu a[href="#{context.tools}"][aria-current="true"]),
               "Tools"
             )
    end

    test "list the dose calculator, with a line that says what it does", context do
      view = open(context, context.tools)

      assert has_element?(view, ~s(ul[data-tools] a[href="#{context.dose}"]), "Dose calculator")
      assert has_element?(view, "ul[data-tools] small", "A body weight times a dose rate")
    end

    test "have a link on the first page of the organisation", context do
      view = open(context, context.home)

      assert has_element?(view, ~s(nav a[href="#{context.tools}"]), "Use the tools")
    end

    test "are for a member of the organisation only", context do
      assert {:error, {:redirect, _to}} = live(sign_in(build_conn(), user!()), context.tools)
      assert {:error, {:redirect, _to}} = live(sign_in(build_conn(), user!()), context.dose)
      assert {:error, {:redirect, _to}} = live(build_conn(), context.dose)
    end
  end

  describe "the dose calculator" do
    test "is in the part Tools, below a breadcrumb", context do
      view = open(context, context.dose)

      assert has_element?(view, "h1", "Dose calculator")

      assert has_element?(
               view,
               ~s(nav[aria-label="Breadcrumb"] a[href="#{context.tools}"]),
               "Tools"
             )

      assert has_element?(view, ~s(#site-menu a[href="#{context.tools}"][aria-current="true"]))
    end

    test "says at all times to check with a vet, and nothing closes that", context do
      view = open(context, context.dose)

      assert has_element?(view, "aside#vet-note h2", "Check with your vet")
      assert has_element?(view, "aside#vet-note", "It does not know the medication")
      assert has_element?(view, "aside#vet-note", "Check the result with your vet")
      refute has_element?(view, "aside#vet-note button")

      calculate(view, %{"weight" => "4", "rate" => "2"})
      assert has_element?(view, "aside#vet-note h2", "Check with your vet")
    end

    test "has a text field with a decimal keyboard for each number, and no number field",
         context do
      view = open(context, context.dose)

      for field <- ~w(weight rate strength) do
        assert has_element?(view, ~s(input#dose_#{field}[type="text"][inputmode="decimal"]))
        assert has_element?(view, ~s(label[for="dose_#{field}"]))
      end

      refute has_element?(view, ~s(input[type="number"]))
    end

    test "offers each unit in a list, the kilogram and the milligram first", context do
      view = open(context, context.dose)

      for {field, units} <- [
            weight_unit: ~w(kg g lb oz),
            rate_unit: ~w(mg mcg g mL),
            strength_unit: ~w(mg mcg g),
            strength_per: ~w(mL tablet)
          ] do
        assert has_element?(view, ~s(label[for="dose_#{field}"]))

        offered =
          view
          |> element("select#dose_#{field}")
          |> render()
          |> LazyHTML.from_fragment()
          |> LazyHTML.query("option")
          |> LazyHTML.attribute("value")

        assert offered == units
      end

      assert has_element?(view, ~s(select#dose_weight_unit option[value="kg"][selected]))
      assert has_element?(view, ~s(select#dose_rate_unit option[value="mg"][selected]))
      refute render(view) =~ "µg"
    end

    test "gives the volume, what went in, and each step of the working", context do
      view = open(context, context.dose)

      refute has_element?(view, "#dose-amount")

      calculate(view, %{
        "weight" => "1095",
        "weight_unit" => "g",
        "rate" => "0.2",
        "strength" => "1.5"
      })

      assert has_element?(view, "#dose-result h2", "Result")
      assert has_element?(view, ~s(#dose-result output[form="dose"] strong), "0.146 mL")
      assert has_element?(view, "#dose-result output", "which holds a dose of 0.219 mg")

      assert has_element?(view, "#dose-result dl", "1,095 g")
      assert has_element?(view, "#dose-result dl", "0.2 mg for each kg of body weight")
      assert has_element?(view, "#dose-result dl", "1.5 mg in each mL")

      assert has_element?(view, "ol[data-working] li:nth-child(1)", "1,095 g = 1.095 kg")

      assert has_element?(
               view,
               "ol[data-working] li:nth-child(2)",
               "1.095 kg × 0.2 mg/kg = 0.219 mg"
             )

      assert has_element?(
               view,
               "ol[data-working] li:nth-child(3)",
               "0.219 mg ÷ 1.5 mg/mL = 0.146 mL"
             )

      assert has_element?(view, "#dose-result", "Check this result with your vet")
      refute has_element?(view, "#dose-result [data-note]")
    end

    test "gives a number of tablets, and does not round it to a tablet", context do
      view = open(context, context.dose)

      calculate(view, %{
        "weight" => "12.4",
        "rate" => "5",
        "strength" => "50",
        "strength_per" => "tablet"
      })

      assert has_element?(view, "#dose-result output strong", "1.24 tablets")
      assert has_element?(view, "#dose-result", "your vet decides how to round it")
    end

    test "gives the dose alone with no strength", context do
      view = open(context, context.dose)

      calculate(view, %{"weight" => "12.4", "rate" => "5"})

      assert has_element?(view, "#dose-result output strong", "62 mg")
      assert has_element?(view, "#dose-result output", "is the dose")
      refute has_element?(view, "#dose-result dl", "in each")
    end

    test "says about before a number that it rounded", context do
      view = open(context, context.dose)

      calculate(view, %{"weight" => "7", "rate" => "1", "strength" => "3"})

      assert has_element?(view, "#dose-result output strong", "about 2.33 mL")
      assert has_element?(view, "ol[data-working] li", "7 mg ÷ 3 mg/mL = about 2.33333 mL")
    end

    test "says when the result is too small to measure", context do
      view = open(context, context.dose)

      calculate(view, %{"weight" => "0.1", "rate" => "0.01", "strength" => "1"})

      assert has_element?(view, "#dose-result [data-note]", "less than 0.01 mL")
      assert has_element?(view, "#dose-result [data-note]", "Ask your vet")
    end

    test "has no strength for a dose rate in mL, and keeps what was typed there", context do
      view = open(context, context.dose)

      view
      |> form("#dose", dose: fields(%{"weight" => "3.2", "rate" => "0.5", "strength" => "9"}))
      |> render_change()

      assert has_element?(view, "#dose-strength-part")

      # The browser sends no strength when the form has none.
      render_change(view, "change", %{
        "dose" => %{
          "weight" => "3.2",
          "weight_unit" => "kg",
          "rate" => "0.5",
          "rate_unit" => "mL"
        }
      })

      refute has_element?(view, "#dose-strength-part")
      assert has_element?(view, "#dose-no-strength", "gives a volume")

      render_submit(view, "calculate", %{
        "dose" => %{
          "weight" => "3.2",
          "weight_unit" => "kg",
          "rate" => "0.5",
          "rate_unit" => "mL"
        }
      })

      assert has_element?(view, "#dose-result output strong", "1.6 mL")
      assert has_element?(view, "#dose-result output", "is the dose")
      refute has_element?(view, "#dose-result dl", "Strength")

      render_change(view, "change", %{
        "dose" => fields(%{"weight" => "3.2", "rate" => "0.5"}) |> Map.drop(["strength"])
      })

      assert has_element?(view, ~s(input#dose_strength[value="9"]))
    end

    test "takes the result away when a field changes", context do
      view = open(context, context.dose)
      typed = %{"weight" => "12.4", "rate" => "5"}

      calculate(view, typed)
      assert has_element?(view, "#dose-amount")

      # The same fields again change nothing.
      view |> form("#dose", dose: fields(typed)) |> render_change()
      assert has_element?(view, "#dose-amount")

      view |> form("#dose", dose: fields(%{typed | "weight" => "12.5"})) |> render_change()
      refute has_element?(view, "#dose-amount")

      calculate(view, %{typed | "weight" => "12.5"})
      assert has_element?(view, "#dose-result output strong", "62.5 mg")

      view |> form("#dose", dose: fields(Map.put(typed, "weight_unit", "g"))) |> render_change()
      refute has_element?(view, "#dose-amount")
    end

    test "refuses a number with a comma, and says how to write it", context do
      view = open(context, context.dose)

      calculate(view, %{"weight" => "1,095", "weight_unit" => "g", "rate" => "0.2"})

      refute has_element?(view, "#dose-amount")
      assert has_element?(view, ~s(input#dose_weight[aria-invalid="true"][value="1,095"]))
      assert has_element?(view, "#dose_weight-error", "no comma")
      assert has_element?(view, ~s(input#dose_weight[aria-describedby="dose_weight-error"]))
      assert has_element?(view, ~s(form#dose p[role="alert"]), "There is no result yet")
      refute has_element?(view, ~s(input#dose_rate[aria-invalid="true"]))
    end

    test "says each field that it refuses", context do
      view = open(context, context.dose)

      calculate(view, %{"weight" => "", "rate" => "-2", "strength" => "1e3"})

      assert has_element?(view, "#dose_weight-error", "Type the body weight.")
      assert has_element?(view, "#dose_rate-error", "no comma")
      assert has_element?(view, "#dose_strength-error", "no comma")
      refute has_element?(view, "#dose-amount")

      calculate(view, %{"weight" => "0", "rate" => "0.0"})

      assert has_element?(view, "#dose_weight-error", "must be above zero")
      assert has_element?(view, "#dose_rate-error", "must be above zero")
    end

    test "takes the words about a field away when a field changes", context do
      view = open(context, context.dose)

      calculate(view, %{"weight" => "four", "rate" => "2"})
      assert has_element?(view, "#dose_weight-error")

      view |> form("#dose", dose: fields(%{"weight" => "4", "rate" => "2"})) |> render_change()
      refute has_element?(view, "#dose_weight-error")
      refute has_element?(view, ~s(form#dose p[role="alert"]))
    end

    test "gives no result for a unit that the lists do not offer", context do
      view = open(context, context.dose)

      for {change, field} <- [
            {%{"weight_unit" => "st"}, "weight"},
            {%{"weight_unit" => "mL"}, "weight"},
            {%{"rate_unit" => "kg"}, "rate"},
            {%{"rate_unit" => "IU"}, "rate"},
            {%{"strength_unit" => "mL"}, "strength"},
            {%{"strength_per" => "kg"}, "strength"}
          ] do
        sent = fields(Map.merge(%{"weight" => "4", "rate" => "2", "strength" => "5"}, change))
        render_submit(view, "calculate", %{"dose" => sent})

        refute has_element?(view, "#dose-amount"), inspect(change)
        assert has_element?(view, "#dose_#{field}-error", "from the list"), inspect(change)
      end
    end

    test "stays up for a request that a person forged", context do
      view = open(context, context.dose)

      for sent <- [
            %{"dose" => "no map"},
            %{"dose" => %{"weight" => %{"a" => "1"}, "rate" => ["2"]}},
            %{"dose" => %{"weight" => ["4"], "weight_unit" => %{}, "no_such_field" => "1"}},
            %{"no" => "dose"},
            %{}
          ] do
        render_submit(view, "calculate", sent)
        render_change(view, "change", sent)
        refute has_element?(view, "#dose-amount")
      end

      render_hook(view, "no-such-event", %{})
      assert has_element?(view, "h1", "Dose calculator")
    end

    test "stores nothing: a result is gone when the page opens again", context do
      view = open(context, context.dose)
      calculate(view, %{"weight" => "12.4", "rate" => "5"})
      assert has_element?(view, "#dose-amount")

      view = open(context, context.dose)
      refute has_element?(view, "#dose-amount")
      assert has_element?(view, ~s(input#dose_weight[value=""]))
    end
  end
end
