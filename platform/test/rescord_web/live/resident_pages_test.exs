defmodule RescordWeb.ResidentPagesTest do
  @moduledoc """
  Holds the pages of the residents and of the lists of values: who can open
  each page, what each role sees, and what a form does.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Lists, Residents}

  setup context do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     base: ~p"/o/#{organisation.short_name}",
     options: [actor: member, tenant: organisation],
     conn: sign_in(context.conn, member)}
  end

  defp open(conn, path) do
    {:ok, view, _html} = live(conn, path)
    {view, render_async(view)}
  end

  # Sends a form, and opens the page that the answer leads to.
  defp submit(view, conn, selector, fields) do
    {:ok, view, _html} =
      view |> form(selector, fields) |> render_submit() |> follow_redirect(conn)

    {view, render_async(view)}
  end

  defp press(view, conn, event) do
    {:ok, view, _html} = view |> render_click(event, %{}) |> follow_redirect(conn)
    {view, render_async(view)}
  end

  describe "the pages" do
    test "do not open for a user of another organisation, or with no sign-in", context do
      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)
      resident = resident!(lists!(context.organisation, context.root), context.options)

      for path <- [
            "/lists",
            "/residents",
            "/residents/new",
            "/residents/#{resident.id}",
            "/residents/#{resident.id}/edit"
          ] do
        assert {:error, {:redirect, %{to: "/"}}} =
                 build_conn() |> sign_in(outsider) |> live(context.base <> path)

        assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), context.base <> path)
      end
    end

    test "of the shared lists open only for a root user", context do
      assert {:error, {:redirect, %{to: "/"}}} = live(context.conn, ~p"/root/lists")

      assert {:error, {:redirect, %{to: "/"}}} =
               build_conn() |> sign_in(context.administrator) |> live(~p"/root/lists")

      {_view, html} = build_conn() |> sign_in(context.root) |> open(~p"/root/lists")
      assert html =~ "Shared lists"
    end

    test "lead to each other from the page of the organisation", context do
      {_view, html} = open(context.conn, context.base)

      assert html =~ ~s(href="#{context.base}/residents")
      assert html =~ ~s(href="#{context.base}/lists")
    end
  end

  describe "the shared lists page" do
    test "lets a root user add a shared value, and says when it is there already", context do
      conn = build_conn() |> sign_in(context.root)
      {view, html} = open(conn, ~p"/root/lists")

      assert html =~ "Species"
      assert html =~ "The list is empty."

      {view, html} = submit(view, conn, "#add-species", value: %{name: "Guinea pig"})
      assert html =~ "Guinea pig"

      html = view |> form("#add-species", value: %{name: "guinea pig"}) |> render_submit()
      assert has_element?(view, "main p[role=alert]")
      assert html =~ "is in the list already"
    end
  end

  describe "the lists page of an organisation" do
    setup context do
      {:ok, dog} = Lists.add_shared_value(:species, "Dog", actor: context.root)
      {:ok, dog: dog}
    end

    test "shows the lists to a member, with no form", context do
      Lists.add_local_value(:species, "Degu", actor: context.root, tenant: context.organisation)

      {view, html} = open(context.conn, context.base <> "/lists")

      assert html =~ "Degu"
      assert html =~ "(local)"
      refute html =~ ~s(phx-submit="add")
      refute html =~ ~s(phx-submit="use")

      # An event that the page did not offer is refused.
      render_submit(view, "add", %{"dimension" => "species", "value" => %{"name" => "Hen"}})
      assert has_element?(view, "main p[role=alert]")
      assert {:ok, [_degu]} = Lists.values(:species, context.options)
    end

    test "lets an administrator add a shared value and a local value", context do
      conn = build_conn() |> sign_in(context.administrator)
      {view, html} = open(conn, context.base <> "/lists")

      assert html =~ "A shared value for species"

      {view, html} = submit(view, conn, "#use-species", value: %{base_id: context.dog.id})
      assert html =~ "Dog"
      assert html =~ "(shared)"
      # The organisation uses each shared value of the species now.
      refute has_element?(view, "#use-species")

      {_view, html} = submit(view, conn, "#add-species", value: %{name: "Degu"})
      assert html =~ "Degu"

      assert {:ok, values} = Lists.values(:species, context.options)
      assert Enum.map(values, &to_string(&1.label)) == ["Degu", "Dog"]
    end

    test "does nothing for a dimension that is not one", context do
      conn = build_conn() |> sign_in(context.administrator)
      {view, _html} = open(conn, context.base <> "/lists")

      render_submit(view, "add", %{"dimension" => "no_such", "value" => %{"name" => "X"}})
      refute has_element?(view, "main p[role=alert]")
    end
  end

  describe "the units of a kind of measurement and the days before expiry" do
    test "are on the lists page, and an administrator changes them", context do
      lists = lists!(context.organisation, context.root)
      conn = build_conn() |> sign_in(context.administrator)
      {view, html} = open(conn, context.base <> "/lists")

      assert html =~ "Units: any unit"
      assert html =~ "Expires soon: 30 days, the default before its date"

      {view, html} =
        submit(view, conn, "#units-#{lists.measure_kind.weight}",
          units: %{ids: [lists.unit.g, lists.unit.kg]}
        )

      assert html =~ "Units: g, kg"

      {_view, html} =
        submit(view, conn, "#soon-#{lists.item_category.medication}", soon: %{days: "60"})

      assert html =~ "Expires soon: 60 days before its date"

      assert Enum.sort(Lists.unit_ids_of_kind(lists.measure_kind.weight, context.options)) ==
               Enum.sort([lists.unit.g, lists.unit.kg])

      # A member reads them, and has no form.
      {_view, html} = open(context.conn, context.base <> "/lists")
      assert html =~ "Units: g, kg"
      refute html =~ ~s(phx-submit="set_units")
      refute html =~ ~s(phx-submit="set_soon_days")
    end

    test "say which units Rescord converts, on each lists page", context do
      lists!(context.organisation, context.root)
      {:ok, _litre} = Lists.add_shared_value(:unit, "Litres", actor: context.root)

      {_view, html} = open(context.conn, context.base <> "/lists")

      assert html =~ "Rescord converts it: gram, a mass"
      assert html =~ "Rescord converts it: kilogram, a mass"
      # `bag` is a name of the organisation.
      assert length(String.split(html, "Rescord does not know this unit")) == 2

      # No other list says it.
      refute html =~ "Rescord converts it: metre"

      {_view, html} = build_conn() |> sign_in(context.root) |> open(~p"/root/lists")
      assert html =~ "Rescord converts it: litre, a volume"
    end

    test "take no value of another list, and read a forged field as no value", context do
      lists = lists!(context.organisation, context.root)
      admin = [actor: context.administrator, tenant: context.organisation]
      {:ok, _weight} = Lists.set_units(lists.measure_kind.weight, [lists.unit.g], admin)
      {:ok, _food} = Lists.set_soon_days(lists.item_category.food, 10, admin)
      conn = build_conn() |> sign_in(context.administrator)
      {view, _html} = open(conn, context.base <> "/lists")

      # A species is not a kind of measurement: the page changes nothing.
      render_submit(view, "set_units", %{
        "value_id" => lists.species.guinea_pig,
        "units" => %{"ids" => [lists.unit.kg]}
      })

      assert Lists.unit_ids_of_kind(lists.measure_kind.weight, admin) == [lists.unit.g]

      assert {:error, {:live_redirect, _to}} =
               render_submit(view, "set_units", %{
                 "value_id" => lists.measure_kind.weight,
                 "units" => %{"ids" => %{"a" => "map"}}
               })

      assert Lists.unit_ids_of_kind(lists.measure_kind.weight, admin) == []

      {view, _html} = open(conn, context.base <> "/lists")

      assert {:error, {:live_redirect, _to}} =
               render_submit(view, "set_soon_days", %{
                 "value_id" => lists.item_category.food,
                 "soon" => %{"days" => %{"a" => "map"}}
               })

      assert {:ok, values} = Lists.values(:item_category, admin)
      assert %{soon_days: nil} = Enum.find(values, &(&1.id == lists.item_category.food))
    end
  end

  describe "a value that an administrator retires" do
    test "stays on the lists page, with a button to restore it", context do
      lists = lists!(context.organisation, context.root)
      conn = build_conn() |> sign_in(context.administrator)
      {view, html} = open(conn, context.base <> "/lists")

      assert html =~ ~s(aria-label="Retire Rex from breed")

      {:ok, view, _html} =
        view
        |> render_click("retire", %{"dimension" => "breed", "id" => lists.breed.rex})
        |> follow_redirect(conn)

      html = render_async(view)
      assert html =~ "(local, retired)"
      assert html =~ ~s(aria-label="Restore Rex to breed")
      refute html =~ ~s(aria-label="Retire Rex from breed")

      # A member sees that it is retired, and has no button.
      {_view, html} = open(context.conn, context.base <> "/lists")
      assert html =~ "(local, retired)"
      refute html =~ ~s(phx-click="restore")
      refute html =~ ~s(phx-click="retire")
    end

    test "is not in the form of a new resident, and is in the form of one that has it", context do
      lists = lists!(context.organisation, context.root)
      resident = resident!(lists, context.options, %{breed_ids: [lists.breed.rex]})
      admin = [actor: context.administrator, tenant: context.organisation]
      {:ok, _} = Lists.retire_value(:breed, lists.breed.rex, admin)
      {:ok, _} = Lists.retire_value(:breed, lists.breed.sheltie, admin)

      {view, _html} = open(context.conn, context.base <> "/residents/new")
      refute has_element?(view, ~s(input[type="checkbox"][value="#{lists.breed.rex}"]))
      assert has_element?(view, ~s(input[type="checkbox"][value="#{lists.breed.abyssinian}"]))

      {view, _html} = open(context.conn, context.base <> "/residents/#{resident.id}/edit")
      assert has_element?(view, ~s(input[type="checkbox"][value="#{lists.breed.rex}"][checked]))
      refute has_element?(view, ~s(input[type="checkbox"][value="#{lists.breed.sheltie}"]))

      # A change to another fact keeps the retired breed.
      {_view, html} = submit(view, context.conn, "#resident", resident: %{name: "Bis"})
      assert html =~ "Bis"
      assert html =~ "Rex"
    end
  end

  describe "the removal of a resident" do
    test "is on the page for an administrator, and not for a member", context do
      lists = lists!(context.organisation, context.root)
      resident = resident!(lists, context.options)
      path = context.base <> "/residents/#{resident.id}"

      {view, html} = open(context.conn, path)
      refute html =~ "Remove this resident"

      # An event that the page did not offer is refused.
      render_click(view, "remove_resident", %{})
      assert has_element?(view, "main p[role=alert]")
      assert [_resident] = Residents.residents!(context.options)

      conn = build_conn() |> sign_in(context.administrator)
      {view, html} = open(conn, path)
      assert html =~ "Remove this resident"

      {:ok, view, _html} = view |> render_click("remove_resident", %{}) |> follow_redirect(conn)
      html = render_async(view)

      assert html =~ "The resident is removed."
      refute html =~ "Biscuit"
      assert Residents.residents!(context.options) == []
    end
  end

  describe "the residents page" do
    test "lists the residents with their species and their status", context do
      lists = lists!(context.organisation, context.root)
      resident = resident!(lists, context.options)
      Residents.register_resident!(%{species_id: lists.species.rabbit}, context.options)

      {_view, html} = open(context.conn, context.base <> "/residents")

      assert html =~ "Biscuit"
      assert html =~ ~s(href="#{context.base}/residents/#{resident.id}")
      assert html =~ "Guinea pig"
      assert html =~ "In care"
      assert html =~ "No name yet"
      assert html =~ "Expected"
      assert html =~ "New resident"
    end
  end

  describe "the form of a resident" do
    test "says that a resident needs a species, when the list has none", context do
      {_view, html} = open(context.conn, context.base <> "/residents/new")
      assert html =~ "The list of species is empty"
    end

    test "records a new resident with its facts and its arrival", context do
      lists = lists!(context.organisation, context.root)
      {view, html} = open(context.conn, context.base <> "/residents/new")

      assert html =~ "Guinea pig"
      assert html =~ "Abyssinian"

      {_view, html} =
        submit(view, context.conn, "#resident",
          resident: %{
            name: "Biscuit",
            species_id: lists.species.guinea_pig,
            sex: "male",
            desex_status: "desexed",
            born_on: "2025-03-01",
            born_on_estimated: "true",
            coat_id: lists.coat.rough,
            breed_ids: [lists.breed.abyssinian],
            colour_ids: [lists.colour.white, lists.colour.tan],
            arrival_kind: "surrender",
            arrived_on: "2026-09-12",
            arrival_note: "With his sister Pepper"
          }
        )

      assert html =~ "Biscuit"
      assert html =~ "In care"
      assert html =~ "Desexed"
      assert html =~ "About 1 March 2025"
      assert html =~ "Abyssinian"
      assert html =~ "Tan, White"
      assert html =~ "Rough"
      assert html =~ "Surrender by an owner, 12 September 2026"
      assert html =~ "With his sister Pepper"

      assert [resident] = Residents.residents!([load: [:name, :status]] ++ context.options)
      assert {resident.name, resident.status} == {"Biscuit", :in_care}
    end

    test "records a resident that is expected, with only a species", context do
      lists = lists!(context.organisation, context.root)
      {view, _html} = open(context.conn, context.base <> "/residents/new")

      {_view, html} =
        submit(view, context.conn, "#resident", resident: %{species_id: lists.species.rabbit})

      assert html =~ "A resident with no name"
      assert html =~ "Expected"
      assert html =~ "Record the arrival"
    end

    test "says what is wrong, and keeps what the person typed", context do
      lists = lists!(context.organisation, context.root)
      {view, _html} = open(context.conn, context.base <> "/residents/new")

      html =
        view
        |> form("#resident",
          resident: %{
            name: "Biscuit",
            species_id: lists.species.guinea_pig,
            arrival_kind: "stray",
            breed_ids: [lists.breed.rex]
          }
        )
        |> render_submit()

      assert has_element?(view, "main p[role=alert]")
      assert html =~ "Arrived on is necessary with the kind of the arrival"
      assert html =~ ~s(value="Biscuit")
      assert has_element?(view, ~s(input[type="checkbox"][value="#{lists.breed.rex}"][checked]))
      assert Residents.residents!(context.options) == []
    end

    test "changes the facts of a resident, and the page then shows the names it had", context do
      lists = lists!(context.organisation, context.root)
      resident = resident!(lists, context.options, %{breed_ids: [lists.breed.rex]})

      {view, html} = open(context.conn, context.base <> "/residents/#{resident.id}/edit")

      assert html =~ ~s(value="Biscuit")
      assert has_element?(view, ~s(input[type="checkbox"][value="#{lists.breed.rex}"][checked]))
      # The arrival is not a part of a change.
      refute html =~ "The arrival"

      {_view, html} =
        submit(view, context.conn, "#resident",
          resident: %{name: "Bis", sex: "female", breed_ids: [lists.breed.sheltie]}
        )

      assert html =~ "Bis"
      assert html =~ "Female"
      assert html =~ "Sheltie"
      refute html =~ "Rex"
      assert html =~ "Names"
      assert html =~ "Biscuit, from"
    end

    test "does not open for a resident that is not there", context do
      for path <- ["/residents/#{Ash.UUID.generate()}", "/residents/not-an-id/edit"] do
        assert {:error, {:redirect, %{to: to}}} = live(context.conn, context.base <> path)
        assert to == context.base <> "/residents"
      end
    end
  end

  describe "the page of a resident" do
    setup context do
      lists = lists!(context.organisation, context.root)

      resident =
        Residents.register_resident!(
          %{name: "Caramel", species_id: lists.species.guinea_pig},
          context.options
        )

      {:ok, lists: lists, resident: resident, path: context.base <> "/residents/#{resident.id}"}
    end

    defp status_of(context) do
      {:ok, resident} = Residents.resident_with_facts(context.resident.id, context.options)
      resident.status
    end

    # A time some seconds ago, as a member types it: a local time of the
    # organisation.
    defp ago(context, seconds) do
      DateTime.utc_now()
      |> DateTime.add(-seconds, :second)
      |> DateTime.shift_zone!(context.organisation.time_zone)
      |> DateTime.to_naive()
      |> NaiveDateTime.truncate(:second)
      |> NaiveDateTime.to_iso8601()
    end

    defp status_at(context, instant) do
      {:ok, resident} =
        Residents.resident_with_facts(context.resident.id, [as_of: instant] ++ context.options)

      resident.status
    end

    test "takes the time that the resident went away and came back", context do
      conn = context.conn
      {view, _html} = open(conn, context.path)

      {view, _html} =
        submit(view, conn, "#arrival",
          arrival: %{kind: "stray", arrived_on: Date.to_iso8601(Date.utc_today())}
        )

      before = DateTime.utc_now()
      Process.sleep(2100)

      # The member says that the resident went away a second ago.
      {view, _html} =
        submit(view, conn, "#absence", absence: %{reason: "At the clinic", at: ago(context, 1)})

      away = DateTime.utc_now()
      assert status_at(context, before) == :in_care
      assert status_of(context) == :away
      Process.sleep(3100)

      # And that it came back a second ago.
      {view, _html} = submit(view, conn, "#back", back: %{at: ago(context, 1)})

      assert status_at(context, away) == :away
      assert status_of(context) == :in_care

      # A time after now is refused.
      tomorrow =
        context.organisation |> Rescord.Accounts.today() |> Date.add(1) |> Date.to_iso8601()

      view
      |> form("#absence", absence: %{reason: "A weekend", at: tomorrow <> "T08:00"})
      |> render_submit()

      assert has_element?(view, "main p[role=alert]", "The time cannot be after now")
      assert status_of(context) == :in_care
    end

    test "follows the stay: the arrival, an absence, and the departure", context do
      conn = context.conn
      {view, html} = open(conn, context.path)

      assert html =~ "Expected"
      # A resident that is not here cannot be away, and cannot leave.
      refute has_element?(view, "#absence")
      refute has_element?(view, "#departure")

      {view, html} =
        submit(view, conn, "#arrival",
          arrival: %{kind: "stray", arrived_on: Date.to_iso8601(Date.utc_today())}
        )

      assert html =~ "The arrival is recorded."
      assert html =~ "Stray"
      assert status_of(context) == :in_care
      refute has_element?(view, "#arrival")

      {view, html} = submit(view, conn, "#absence", absence: %{reason: "At the clinic"})
      assert html =~ "Away for a time"
      assert html =~ "At the clinic"
      assert status_of(context) == :away

      {view, _html} = press(view, conn, "finish_absence")
      assert status_of(context) == :in_care

      {view, html} =
        submit(view, conn, "#departure",
          departure: %{
            kind: "transfer_out",
            departed_on: Date.to_iso8601(Date.utc_today()),
            note: "To Banksia Road"
          }
        )

      assert html =~ "Left"
      assert html =~ "Transfer to another organisation"
      assert html =~ "To Banksia Road"
      assert status_of(context) == :left

      {_view, html} = press(view, conn, "withdraw_departure")
      assert html =~ "In care"
      assert status_of(context) == :in_care
    end

    test "says what is wrong with a date after today", context do
      {view, _html} = open(context.conn, context.path)

      html =
        view
        |> form("#arrival",
          arrival: %{kind: "stray", arrived_on: Date.to_iso8601(Date.add(Date.utc_today(), 3))}
        )
        |> render_submit()

      assert has_element?(view, "main p[role=alert]")
      assert html =~ "Arrived on cannot be after today"
      assert status_of(context) == :expected
    end

    test "adds an identifier, and removes it", context do
      conn = context.conn
      {view, html} = open(conn, context.path)

      # A resident needs no identifier: the page has the form, and no
      # sentence about an identifier that is not there.
      assert has_element?(view, "#identifiers-heading", "Identifiers")
      assert has_element?(view, "form#identifier")
      refute html =~ "No identifier"

      {view, html} =
        submit(view, conn, "#identifier",
          identifier: %{
            kind_id: context.lists.identifier_kind.microchip,
            value: "956000012345678"
          }
        )

      assert html =~ "Microchip: 956000012345678"
      assert html =~ ~s(aria-label="Remove the Microchip 956000012345678")

      {:ok, %{identifiers: [identifier]}} =
        Residents.resident_with_facts(context.resident.id, context.options)

      {:ok, view, _html} =
        view
        |> render_click("remove_identifier", %{"id" => identifier.id})
        |> follow_redirect(conn)

      html = render_async(view)
      refute html =~ "Microchip: 956000012345678"
      refute html =~ "No identifier"
      assert has_element?(view, "form#identifier")

      # An identifier that is not one of this resident does nothing.
      render_click(view, "remove_identifier", %{"id" => Ash.UUID.generate()})
      refute has_element?(view, "main p[role=alert]")
    end

    test "has no section of identifiers when there is none to show or to add", context do
      admin = [actor: context.administrator, tenant: context.organisation]
      kinds = context.lists.identifier_kind

      tagged = resident!(context.lists, context.options, %{name: "Biscuit"})

      Residents.add_identifier!(
        %{resident_id: tagged.id, kind_id: kinds.ear_tag, value: "WC-041"},
        context.options
      )

      # The refuge uses no identifier: an administrator retires each kind.
      {:ok, _} = Lists.retire_value(:identifier_kind, kinds.microchip, admin)
      {:ok, _} = Lists.retire_value(:identifier_kind, kinds.ear_tag, admin)

      {view, html} = open(context.conn, context.path)
      refute has_element?(view, "#identifiers-heading")
      refute html =~ "identifier"

      # A resident that has an identifier keeps it on its page, with no form.
      {view, html} = open(context.conn, context.base <> "/residents/#{tagged.id}")
      assert has_element?(view, "#identifiers-heading", "Identifiers")
      assert html =~ "Ear tag: WC-041"
      refute has_element?(view, "form#identifier")
    end
  end
end
