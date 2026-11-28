defmodule RescordWeb.JournalPagesTest do
  @moduledoc """
  Holds the page of the journal of a resident: who can open it, what the
  form of an entry does for each kind, and who can correct an entry. The
  tests find what a person finds (ADR 0107): an entry is an article, named
  by its kind and its time.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Phoenix.LiveViewTest,
    only: [
      assert_patch: 1,
      element: 2,
      render_async: 1,
      render_change: 2,
      render_submit: 2,
      render_submit: 3
    ]

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.Journal

  setup context do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    {_, other} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    options = [actor: member, tenant: organisation]
    biscuit = resident!(lists, options)

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     other: other,
     lists: lists,
     options: options,
     biscuit: biscuit,
     resident_path: ~p"/o/#{organisation.short_name}/residents/#{biscuit.id}",
     path: ~p"/o/#{organisation.short_name}/residents/#{biscuit.id}/journal",
     conn: sign_in(context.conn, member)}
  end

  # The page lists its entries with Cinder, which loads them after the
  # first render.
  defp open(conn, path), do: conn |> visit(path) |> unwrap(&render_async/1)
  defp open_as(user, path), do: build_conn() |> sign_in(user) |> open(path)

  defp journal, do: main() |> region("Entries")
  defp card(name), do: journal() |> article(name)
  defp new_entry, do: main() |> details("New journal entry")
  defp unit, do: new_entry() |> field("Unit")

  defp write(session), do: session |> click(button("Write the entry")) |> unwrap(&render_async/1)

  # A form that the page did not offer: a unit that the select had not.
  defp forge_unit(session, measure_kind, unit) do
    unwrap(session, fn view ->
      view
      |> Phoenix.LiveViewTest.form("#entry",
        entry: %{kind: "measurement", measure_kind_id: measure_kind}
      )
      |> render_submit(%{entry: %{value: "2", unit_id: unit}})
    end)
  end

  defp entries(context) do
    {:ok, entries} = Journal.entries(context.biscuit.id, context.options)
    entries
  end

  test "the page does not open for a user of another organisation, or with no sign-in", context do
    other = organisation!(context.root, "Other")
    {_, outsider} = member!(other, :administrator, context.root)

    build_conn() |> sign_in(outsider) |> visit(context.path) |> assert_path("/")
    build_conn() |> visit(context.path) |> assert_path("/")

    missing = ~p"/o/#{context.organisation.short_name}/residents/#{Ash.UUID.generate()}/journal"

    context.conn
    |> visit(missing)
    |> assert_path(~p"/o/#{context.organisation.short_name}/residents")
  end

  describe "a new entry" do
    test "has words, the member who wrote it, and the time in the zone of the organisation",
         context do
      session =
        context.conn
        |> open(context.path)
        |> assert_has(journal(), text: "The journal has no entry yet.")
        |> within(new_entry(), fn form ->
          form
          |> select("Kind", option: "Behaviour")
          |> fill_in("What happened", with: "Popcorning at floor time.")
        end)
        |> write()

      [entry] = entries(context)

      local =
        RescordWeb.JournalWords.time(
          Rescord.Accounts.local_time(context.organisation, entry.happened_at)
        )

      # The kind and the time name the card.
      session
      |> assert_has(card("Behaviour #{local}"), text: "Popcorning at floor time.")
      |> assert_has(card("Behaviour #{local}"), text: to_string(context.member.email))
    end

    test "shows the fields of the kind that the member chooses", context do
      session =
        context.conn
        |> open(context.path)
        |> refute_has(new_entry() |> field("Value"))
        |> within(new_entry(), &select(&1, "Kind", option: "Measurement"))
        |> assert_has(new_entry() |> field("What was measured"))
        |> assert_has(new_entry() |> field("Value"))
        |> refute_has(new_entry() |> field("Medication"))

      session
      |> within(new_entry(), &select(&1, "Kind", option: "Prescription"))
      |> assert_has(new_entry() |> field("Medication"))
      |> assert_has(new_entry() |> field("How it is given"))
      |> refute_has(new_entry() |> field("Value"))
    end

    test "offers the units of the kind of measurement, or each unit", context do
      lists = context.lists

      Rescord.Lists.set_units(lists.measure_kind.weight, [lists.unit.g, lists.unit.kg],
        actor: context.administrator,
        tenant: context.organisation
      )

      context.conn
      |> open(context.path)
      |> within(new_entry(), fn form ->
        form
        |> select("Kind", option: "Measurement")
        |> select("What was measured", option: "Weight")
      end)
      |> assert_has(unit(), text: "kg")
      |> refute_has(unit(), text: "bag")
      |> within(new_entry(), &select(&1, "What was measured", option: "Temperature"))
      |> assert_has(unit(), text: "bag")
      # The kind refuses a unit that the form did not offer.
      |> forge_unit(lists.measure_kind.weight, lists.unit.bag)
      |> assert_has(main(), text: "Unit is not a unit of this kind of measurement")
    end

    test "of a kind with a standard unit chooses that unit, and writes the entry in it",
         context do
      lists = context.lists
      admin = [actor: context.administrator, tenant: context.organisation]

      # Recorded in kg before the kind had a standard unit.
      Rescord.Journal.write_entry!(
        %{
          resident_id: context.biscuit.id,
          kind: :measurement,
          measure_kind_id: lists.measure_kind.weight,
          value: "0.61",
          unit_id: lists.unit.kg
        },
        context.options
      )

      {:ok, _} = Rescord.Lists.set_standard_unit(lists.measure_kind.weight, lists.unit.g, admin)

      session =
        context.conn
        |> open(context.path)
        |> assert_has(card(~r/^Measurement\b/), text: "Weight: 610 g (recorded as 0.61 kg)")
        # A correction changes the value as it was recorded.
        |> assert_has(card(~r/^Measurement\b/) |> field("Value, in kg"))
        |> within(new_entry(), &select(&1, "Kind", option: "Measurement"))
        |> assert_has(unit(), text: "No unit")
        |> within(new_entry(), &select(&1, "What was measured", option: "Weight"))
        |> within(unit(), &assert_has(&1, "option[selected]", text: "g", exact: true))
        |> assert_has(unit(), text: "kg")
        |> refute_has(unit(), text: "bag")
        |> refute_has(unit(), text: "No unit")

      assert attribute(session, unit(), "required")

      # The person chooses kg, and the form keeps it while they type.
      session =
        within(session, new_entry(), fn form ->
          form |> select("Unit", option: "kg") |> fill_in("Value", with: "0.7")
        end)

      assert value(session, unit()) == "kg"

      # The kind refuses a unit that the form did not offer.
      session
      |> forge_unit(lists.measure_kind.weight, lists.unit.bag)
      |> assert_has(main(),
        text: "Unit is not a unit that Rescord converts to g, the unit of this kind"
      )
    end

    test "records a weight, and the page of the resident shows the newest one", context do
      context.conn
      |> open(context.path)
      |> within(new_entry(), fn form ->
        form
        |> select("Kind", option: "Measurement")
        |> select("What was measured", option: "Weight")
        |> fill_in("Value", with: "1095")
        |> select("Unit", option: "g")
      end)
      |> write()
      |> assert_has(card(~r/^Measurement\b/), text: "Weight: 1,095 g")
      |> visit(context.resident_path)
      |> unwrap(&render_async/1)
      |> assert_has(main(), text: "1,095 g,")
      |> refute_has(main(), text: "No weight or other measurement yet.")
    end

    test "says what is wrong, and keeps what the member typed", context do
      session =
        context.conn
        |> open(context.path)
        |> within(new_entry(), fn form ->
          form
          |> select("Kind", option: "Vaccination")
          |> fill_in("Vaccine", with: "")
          |> fill_in("Note", with: "Given in the left leg.")
        end)
        |> click(button("Write the entry"))
        |> assert_has(main() |> alert(), text: "Vaccine is required")

      assert value(session, new_entry() |> field("Note")) == "Given in the left leg."
      assert entries(context) == []

      tomorrow =
        context.organisation |> Rescord.Accounts.today() |> Date.add(1) |> Date.to_iso8601()

      session
      |> within(new_entry(), fn form ->
        form
        |> select("Kind", option: "General")
        |> fill_in("What happened", with: "Tomorrow.")
        |> fill_in("When it happened, if not now", with: tomorrow <> "T08:00")
      end)
      |> click(button("Write the entry"))
      |> assert_has(main() |> alert(), text: "The time cannot be after now")

      assert entries(context) == []
    end
  end

  describe "the medical history" do
    test "has the entries of a medical kind only", context do
      Journal.write_entry!(
        %{resident_id: context.biscuit.id, kind: :general, note: "Ate well."},
        context.options
      )

      Journal.write_entry!(
        %{resident_id: context.biscuit.id, kind: :vaccination, vaccine: "A sample vaccine"},
        context.options
      )

      context.conn
      |> open(context.path)
      |> assert_has(journal(), text: "Ate well.")
      |> assert_has(journal(), text: "Vaccine: A sample vaccine")
      # The form of the filters is Cinder's own; it writes the address that
      # the page had before (ADR 0092).
      |> unwrap(fn view ->
        view
        |> element("#journal-filter-form")
        |> render_change(%{"filters" => %{"only" => "medical"}})

        assert assert_patch(view) =~ "only=medical"
        render_async(view)
      end)
      |> refute_has(journal(), text: "Ate well.")
      |> assert_has(journal(), text: "Vaccine: A sample vaccine")

      # And that address opens the medical history.
      context.conn
      |> open(context.path <> "?only=medical")
      |> refute_has(journal(), text: "Ate well.")
      |> assert_has(journal(), text: "Vaccine: A sample vaccine")
    end
  end

  describe "the entries as a collection (ADR 0092)" do
    setup context do
      write = fn facts, days ->
        Journal.write_entry!(
          Map.merge(facts, %{
            resident_id: context.biscuit.id,
            happened_at: DateTime.add(DateTime.utc_now(), -days, :day)
          }),
          context.options
        )
      end

      general = write.(%{kind: :general, note: "Ate well."}, 40)
      vaccination = write.(%{kind: :vaccination, vaccine: "A sample vaccine"}, 20)
      behaviour = write.(%{kind: :behaviour, note: "Popcorning at floor time."}, 1)

      addendum =
        Journal.write_entry!(
          %{
            resident_id: context.biscuit.id,
            kind: :general,
            note: "And drank well.",
            follows_id: general.id
          },
          actor: context.other,
          tenant: context.organisation
        )

      {:ok, general: general, vaccination: vaccination, behaviour: behaviour, addendum: addendum}
    end

    test "reads the search and the filters from the address", context do
      day = fn days -> Date.to_iso8601(Date.add(Date.utc_today(), -days)) end

      for {parameters, shown, hidden} <- [
            {"", ["Ate well.", "A sample vaccine", "Popcorning", "And drank well."], []},
            {"?kind=vaccination", ["A sample vaccine"], ["Ate well.", "Popcorning"]},
            {"?search=popcorn", ["Popcorning"], ["Ate well.", "A sample vaccine"]},
            {"?search=sample+vac", ["A sample vaccine"], ["Ate well.", "Popcorning"]},
            {"?happened_at=#{day.(30)},#{day.(10)}", ["A sample vaccine"],
             ["Ate well.", "Popcorning"]},
            {"?only=medical&search=well", [], ["Ate well.", "A sample vaccine", "Popcorning"]},
            # A value that is no choice changes nothing, and makes no fault.
            {"?only=x&kind=nothing&page=x", ["Ate well.", "A sample vaccine", "Popcorning"], []}
          ] do
        session = open(context.conn, context.path <> parameters)

        for words <- shown, do: assert_has(session, journal(), text: words)
        for words <- hidden, do: refute_has(session, journal(), text: words)
      end

      context.conn
      |> open(context.path <> "?search=nothing+such")
      |> assert_has(journal(), text: "No entry matches the search and the filters.")
    end

    test "shows one entry with what was added to it, for a link from another page", context do
      session =
        context.conn
        |> open(context.path <> "?entry=#{context.general.id}")
        |> assert_has(journal(), text: "Ate well.")
        |> assert_has(journal(), text: "And drank well.")
        |> refute_has(journal(), text: "Popcorning")
        |> refute_has(journal(), text: "A sample vaccine")

      assert href(session, main() |> link("Show each entry")) == context.path

      # An id that names no entry of this journal shows the whole journal.
      clover = resident!(context.lists, context.options, %{name: "Clover"})

      theirs =
        Journal.write_entry!(
          %{resident_id: clover.id, kind: :general, note: "Of another resident."},
          context.options
        )

      for id <- [theirs.id, "nothing"] do
        context.conn
        |> open(context.path <> "?entry=#{id}")
        |> assert_has(journal(), text: "Popcorning")
        |> refute_has(main(), text: "Of another resident.")
        |> refute_has(main() |> link("Show each entry"))
      end
    end

    test "takes no event for an entry of another resident", context do
      clover = resident!(context.lists, context.options, %{name: "Clover"})

      theirs =
        Journal.write_entry!(
          %{resident_id: clover.id, kind: :general, note: "Of another resident."},
          context.options
        )

      context.conn
      |> open(context.path)
      |> unwrap(
        &render_submit(&1, "correct", %{
          "entry_id" => theirs.id,
          "entry" => %{"note" => "Changed from the wrong page."}
        })
      )

      assert {:ok, %{note: "Of another resident."}} = Journal.entry(theirs.id, context.options)
    end

    test "has pages of 25 entries, the newest first", context do
      for number <- 10..34 do
        Journal.write_entry!(
          %{
            resident_id: context.biscuit.id,
            kind: :general,
            note: "Note #{number}.",
            happened_at: DateTime.add(DateTime.utc_now(), -number, :hour)
          },
          context.options
        )
      end

      # 29 entries: the newest 25 are on the first page. The buttons of the
      # pages are Cinder's own, with a title and no name.
      context.conn
      |> open(context.path)
      |> assert_has("#entries button[title='Next page']")
      |> assert_has(journal(), text: "And drank well.")
      |> assert_has(journal(), text: "Note 32.")
      |> refute_has(journal(), text: "Note 33.")
      |> refute_has(journal(), text: "Ate well.")

      context.conn
      |> open(context.path <> "?page=2")
      |> assert_has(journal(), text: "Ate well.")
      |> refute_has(journal(), text: "Note 10.")
    end

    test "keeps the search and the filters in the links of the conditions", context do
      Journal.write_entry!(
        %{
          resident_id: context.biscuit.id,
          kind: :diagnosis,
          condition_id: context.lists.condition.respiratory_infection
        },
        context.options
      )

      {:ok, [episode]} = Journal.episodes_of(context.biscuit.id, context.options)
      session = open(context.conn, context.path <> "?only=medical&page=1&search=a")

      assert href(session, main() |> navigation("Conditions") |> link("Respiratory infection")) ==
               "#{context.path}?episode=#{episode.id}&only=medical&search=a"

      # An old address of the form of a diagnosis is the filter on the kind now.
      session =
        context.conn
        |> open(context.path <> "?kind=diagnosis")
        |> assert_has(card(~r/^Diagnosis\b/), text: "Respiratory infection")
        |> refute_has(journal(), text: "Popcorning")

      refute open?(session, new_entry())
    end
  end

  describe "an entry on the page" do
    setup context do
      entry =
        Journal.write_entry!(
          %{resident_id: context.biscuit.id, kind: :examination, note: "Mild chest sounds."},
          context.options
        )

      {:ok, entry: entry}
    end

    defp correct, do: card(~r/^Examination\b/) |> details("Correct this entry")

    test "has a form to correct it for its author and an administrator, and not for another member",
         context do
      context.conn |> open(context.path) |> assert_has(correct())

      context.other
      |> open_as(context.path)
      |> refute_has(correct())
      # An event that the page did not offer is refused.
      |> unwrap(
        &render_submit(&1, "correct", %{
          "entry_id" => context.entry.id,
          "entry" => %{"note" => "No."}
        })
      )
      |> assert_has(main() |> alert())

      assert [%{note: "Mild chest sounds."}] = entries(context)

      context.administrator
      |> open_as(context.path)
      |> within(correct(), fn form ->
        form
        |> fill_in("Note", with: "Mild chest sounds on the left.")
        |> click_button("Save the correction")
      end)
      |> unwrap(&render_async/1)
      |> assert_has(card(~r/^Examination\b/), text: "Mild chest sounds on the left.")

      assert [%{author_id: author}] = entries(context)
      assert author == context.member.id
    end

    test "gets an addendum from another member", context do
      context.other
      |> open_as(context.path)
      |> within(card(~r/^Examination\b/) |> details("Add to this entry"), fn form ->
        form
        |> fill_in("What to add", with: "Clear on the second check.")
        |> click_button("Add to the entry")
      end)
      |> unwrap(&render_async/1)
      |> assert_has(card(~r/^Examination\b/), text: "Clear on the second check.")
      |> assert_has(card(~r/^Examination\b/), text: "Adds to the entry of")
      |> assert_has(card(~r/^Examination\b/), text: to_string(context.other.email))

      assert [addendum, _first] = entries(context)
      assert addendum.follows.id == context.entry.id
      assert addendum.kind == :examination
    end
  end
end
