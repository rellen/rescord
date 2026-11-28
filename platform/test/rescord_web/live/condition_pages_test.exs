defmodule RescordWeb.ConditionPagesTest do
  @moduledoc """
  Holds the pages of the conditions of a resident (ADR 0083): the section
  on the page of a resident, the form of a diagnosis, the filter of the
  journal with the card of a condition and what a member does with it, the
  button for a diagnosis from before, and the page Conditions with its
  counts.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Journal, Lists, Locations}

  doctest RescordWeb.ConditionComponents

  setup context do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)

    {:ok, bumblefoot} =
      Lists.add_local_value(:condition, "Bumblefoot", actor: root, tenant: organisation)

    options = [actor: member, tenant: organisation]
    biscuit = resident!(lists, options)
    base = ~p"/o/#{organisation.short_name}/residents"

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     lists: lists,
     uri: lists.condition.respiratory_infection,
     bumblefoot: bumblefoot.id,
     options: options,
     today: Accounts.today(organisation),
     biscuit: biscuit,
     base: base,
     resident_path: "#{base}/#{biscuit.id}",
     path: "#{base}/#{biscuit.id}/journal",
     conditions_path: "#{base}/conditions",
     conn: sign_in(context.conn, member)}
  end

  defp open(conn, path) do
    {:ok, view, _html} = live(conn, path)
    {view, render_async(view)}
  end

  defp follow(result, conn) do
    {:ok, view, _html} = follow_redirect(result, conn)
    {view, render_async(view)}
  end

  defp diagnose!(context, condition_id, more \\ %{}) do
    %{kind: :diagnosis, condition_id: condition_id, resident_id: context.biscuit.id}
    |> Map.merge(more)
    |> Journal.write_entry!(context.options)
  end

  defp episodes(context, resident \\ nil) do
    {:ok, episodes} = Journal.episodes_of((resident || context.biscuit).id, context.options)
    episodes
  end

  # A member whose role has no power: the person reads, and changes nothing.
  defp reader!(context) do
    options = [actor: context.administrator, tenant: context.organisation]
    {:ok, role} = Accounts.define_role(%{name: "Reader", powers: []}, options)
    {membership, person} = member!(context.organisation, :member, context.administrator)
    {:ok, _member} = Accounts.set_member_role(membership, role.id, options)
    person
  end

  describe "the page of a resident" do
    test "says that no condition is recorded, with a link to record a diagnosis", context do
      {view, html} = open(context.conn, context.resident_path)

      assert html =~ "No condition is recorded now."
      assert has_element?(view, "a[href='#{context.path}?kind=diagnosis']", "Record a diagnosis")
      assert has_element?(view, "a[href='#{context.conditions_path}']")
    end

    test "shows what the resident has now, and what it had in a closed part", context do
      diagnose!(context, context.bumblefoot, %{
        onset_on: Date.add(context.today, -2),
        note: "Left hind foot."
      })

      diagnose!(context, context.uri, %{onset_on: Date.add(context.today, -30), chronic: true})
      [chronic, ongoing] = episodes(context) |> Enum.sort_by(& &1.started_on, Date)

      diagnose!(context, context.uri)
      {:ok, _resolved} = Journal.resolve_episode(chronic, %{}, context.options)

      {view, _html} = open(context.conn, context.resident_path)

      assert has_element?(
               view,
               "#conditions-now a[href='#{context.path}?episode=#{ongoing.id}']",
               "Bumblefoot"
             )

      assert has_element?(view, "#condition-#{ongoing.id}", "Ongoing")
      assert has_element?(view, "#condition-#{ongoing.id} small", "2 days")
      assert has_element?(view, "#condition-#{ongoing.id} small", "1 entry")
      refute has_element?(view, "#conditions-now", "Respiratory infection")

      assert has_element?(view, "#conditions-earlier summary", "1 earlier condition")
      assert has_element?(view, "#conditions-earlier #condition-#{chronic.id}", "Resolved")
      assert has_element?(view, "#conditions-earlier small", "2 entries")
    end

    test "has no link to record a diagnosis for a person who cannot write", context do
      diagnose!(context, context.bumblefoot, %{chronic: true})
      conn = sign_in(build_conn(), reader!(context))

      {view, _html} = open(conn, context.resident_path)

      assert has_element?(view, "#conditions-now", "Chronic")
      refute has_element?(view, "a", "Record a diagnosis")
    end
  end

  describe "the form of a diagnosis" do
    test "opens with the kind diagnosis from the link of the resident", context do
      {view, _html} = open(context.conn, context.path <> "?kind=diagnosis")

      assert has_element?(view, "details#new-entry[open]")
      assert has_element?(view, "#entry select[name='entry[kind]'] option[selected]", "Diagnosis")
      assert has_element?(view, "#entry input[name='entry[onset_on]']")
      assert has_element?(view, "#entry input[name='entry[chronic]']")

      {view, _html} = open(context.conn, context.path)
      refute has_element?(view, "details#new-entry[open]")
    end

    test "starts a condition with its first day and the mark for a chronic one", context do
      {view, _html} = open(context.conn, context.path <> "?kind=diagnosis")
      first = Date.add(context.today, -5)

      {view, _html} =
        view
        |> form("#entry",
          entry: %{
            kind: "diagnosis",
            condition_id: context.bumblefoot,
            onset_on: Date.to_iso8601(first),
            chronic: "true",
            note: "The vet saw it."
          }
        )
        |> render_submit()
        |> follow(context.conn)

      assert [episode] = episodes(context)
      assert episode.started_on == first
      assert episode.chronic
      assert has_element?(view, "nav[aria-label=Conditions] a", "Bumblefoot")
      assert has_element?(view, "p[data-about] a", "Bumblefoot")
    end

    test "says that a diagnosis joins the condition that the resident has now", context do
      diagnose!(context, context.bumblefoot)
      {view, _html} = open(context.conn, context.path <> "?kind=diagnosis")

      refute has_element?(view, "#entry-joins")

      view
      |> form("#entry", entry: %{kind: "diagnosis", condition_id: context.bumblefoot})
      |> render_change()

      assert has_element?(view, "#entry-joins", "Biscuit has Bumblefoot since")
      assert has_element?(view, "#entry-joins", "This entry joins it.")
      refute has_element?(view, "#entry input[name='entry[onset_on]']")
      refute has_element?(view, "#entry input[name='entry[chronic]']")

      view
      |> form("#entry", entry: %{kind: "diagnosis", condition_id: context.uri})
      |> render_change()

      refute has_element?(view, "#entry-joins")
      assert has_element?(view, "#entry input[name='entry[onset_on]']")
    end

    test "says what is wrong with a first day after today", context do
      {view, _html} = open(context.conn, context.path <> "?kind=diagnosis")

      view
      |> form("#entry",
        entry: %{
          kind: "diagnosis",
          condition_id: context.bumblefoot,
          onset_on: context.today |> Date.add(1) |> Date.to_iso8601()
        }
      )
      |> render_submit()

      assert has_element?(view, "main p[role=alert]", "cannot be after today")
      assert episodes(context) == []
    end
  end

  describe "the journal of a resident with a condition" do
    setup context do
      diagnosis = diagnose!(context, context.bumblefoot, %{onset_on: Date.add(context.today, -4)})

      note =
        Journal.write_entry!(
          %{kind: :general, note: "Ate well.", resident_id: context.biscuit.id},
          context.options
        )

      [episode] = episodes(context)

      {:ok,
       diagnosis: diagnosis,
       note: note,
       episode: episode,
       filtered: "#{context.path}?episode=#{episode.id}"}
    end

    test "offers the conditions of the resident for a new entry", context do
      {view, _html} = open(context.conn, context.path)

      assert has_element?(
               view,
               "#entry select[name='entry[episode_id]'] option[value='#{context.episode.id}']",
               "Bumblefoot, since"
             )

      {view, _html} =
        view
        |> form("#entry",
          entry: %{kind: "general", note: "The sore is dry.", episode_id: context.episode.id}
        )
        |> render_submit()
        |> follow(context.conn)

      {:ok, entries} = Journal.entries(context.biscuit.id, context.options)
      written = Enum.find(entries, &(&1.note == "The sore is dry."))
      assert written.episode_id == context.episode.id
      assert has_element?(view, "#entry-#{written.id} p[data-about] a", "Bumblefoot")
      refute has_element?(view, "#entry-#{context.note.id} p[data-about]")
    end

    test "shows the entries about one condition, with its card", context do
      {view, html} = open(context.conn, context.filtered)

      assert html =~ "The entries about Bumblefoot"
      assert has_element?(view, "#entry-#{context.diagnosis.id}")
      refute has_element?(view, "#entry-#{context.note.id}")

      assert has_element?(view, "article#condition h2", "Bumblefoot")
      assert has_element?(view, "article#condition", "Ongoing")
      assert has_element?(view, "article#condition", "4 days, and not over")

      assert has_element?(view, "nav[aria-label=Conditions] a[aria-current=true]", "Bumblefoot")
      refute has_element?(view, "nav[aria-label=Conditions] a[aria-current=true]", "Each entry")

      # The form of a new entry has the condition of the page.
      assert has_element?(
               view,
               "#entry select[name='entry[episode_id]'] option[selected][value='#{context.episode.id}']"
             )

      # The filter works with the medical history.
      {view, html} = open(context.conn, context.filtered <> "&only=medical")
      assert html =~ "The medical history about Bumblefoot"
      assert has_element?(view, "#entry-#{context.diagnosis.id}")
    end

    test "shows each entry for a condition that is not of this resident", context do
      clover = resident!(context.lists, context.options, %{name: "Clover"})

      Journal.write_entry!(
        %{kind: :diagnosis, condition_id: context.uri, resident_id: clover.id},
        context.options
      )

      [other] = episodes(context, clover)

      for id <- [other.id, Ash.UUID.generate(), "not-an-id"] do
        {view, html} = open(context.conn, "#{context.path}?episode=#{id}")

        assert html =~ "Each entry, the newest first"
        refute has_element?(view, "article#condition")
        assert has_element?(view, "#entry-#{context.note.id}")
      end
    end

    test "marks the condition as resolved, opens it again and changes it", context do
      {view, _html} = open(context.conn, context.filtered)
      last = Date.add(context.today, -1)

      {view, _html} =
        view
        |> form("#resolve", episode: %{ended_on: Date.to_iso8601(last)})
        |> render_submit()
        |> follow(context.conn)

      assert [%{ended_on: ^last, state: :resolved}] = episodes(context)
      assert has_element?(view, "article#condition", "Resolved")
      assert has_element?(view, "article#condition", "4 days")
      refute has_element?(view, "#resolve")

      {view, _html} =
        view
        |> form("#revise",
          episode: %{
            started_on: context.today |> Date.add(-9) |> Date.to_iso8601(),
            ended_on: Date.to_iso8601(last),
            chronic: "true",
            note: "left hind foot"
          }
        )
        |> render_submit()
        |> follow(context.conn)

      assert [%{chronic: true, note: "left hind foot"} = revised] = episodes(context)
      assert revised.started_on == Date.add(context.today, -9)
      assert has_element?(view, "article#condition", "left hind foot")

      {view, _html} =
        view
        |> element("#reopen-details button", "Open the condition again")
        |> render_click()
        |> follow(context.conn)

      assert [%{ended_on: nil}] = episodes(context)
      assert has_element?(view, "article#condition", "Chronic")
      assert has_element?(view, "#resolve")
    end

    test "says what is wrong with a last day before the first day", context do
      {view, _html} = open(context.conn, context.filtered)

      view
      |> form("#resolve",
        episode: %{ended_on: context.today |> Date.add(-10) |> Date.to_iso8601()}
      )
      |> render_submit()

      assert has_element?(view, "main p[role=alert]", "cannot be before the first day")
      assert [%{ended_on: nil}] = episodes(context)
    end

    test "is removed by an administrator, and its entries stay", context do
      {view, _html} = open(context.conn, context.filtered)
      refute has_element?(view, "#remove-condition-details")

      # The page of a member does not run the event either.
      render_click(view, "remove_episode", %{})
      assert has_element?(view, "main p[role=alert]")
      assert [_episode] = episodes(context)

      conn = sign_in(build_conn(), context.administrator)
      {view, _html} = open(conn, context.filtered)

      {view, html} =
        view
        |> element("#remove-condition-details button", "Remove the condition")
        |> render_click()
        |> follow(conn)

      assert html =~ "The condition is removed."
      assert episodes(context) == []
      assert has_element?(view, "#entry-#{context.diagnosis.id}")
      refute has_element?(view, "#entry-#{context.diagnosis.id} p[data-about]")
    end

    test "has no form for a person who cannot write, and the events change nothing", context do
      conn = sign_in(build_conn(), reader!(context))
      {view, _html} = open(conn, context.filtered)

      assert has_element?(view, "article#condition h2", "Bumblefoot")

      for part <- ~w(#resolve #revise #reopen-details #remove-condition-details #entry) do
        refute has_element?(view, part)
      end

      render_submit(view, "resolve_episode", %{"episode" => %{"ended_on" => ""}})
      render_submit(view, "revise_episode", %{"episode" => %{"note" => "x"}})
      render_click(view, "reopen_episode", %{})
      render_click(view, "track", %{"entry_id" => context.diagnosis.id})

      assert [%{ended_on: nil, note: nil}] = episodes(context)

      # An event with no map, and an event that the page does not know.
      render_submit(view, "resolve_episode", %{"episode" => "text"})
      render_click(view, "track", %{})
      assert render(view) =~ "Bumblefoot"
    end
  end

  describe "a diagnosis from before" do
    setup context do
      options = [actor: context.administrator, tenant: context.organisation]
      diagnosis = diagnose!(context, context.uri)
      [episode] = episodes(context)
      :ok = Journal.remove_episode(episode, options)
      {:ok, diagnosis: diagnosis}
    end

    test "starts its condition from the button", context do
      {view, _html} = open(context.conn, context.path)
      refute has_element?(view, "nav[aria-label=Conditions]")

      {view, _html} =
        view
        |> element("#track-details-#{context.diagnosis.id} button", "Track this condition")
        |> render_click()
        |> follow(context.conn)

      assert [episode] = episodes(context)
      assert episode.condition_id == context.uri
      assert episode.started_on == context.today
      assert has_element?(view, "nav[aria-label=Conditions] a", "Respiratory infection")
      refute has_element?(view, "#track-details-#{context.diagnosis.id}")
    end

    test "has no button for a person who cannot write", context do
      conn = sign_in(build_conn(), reader!(context))
      {view, _html} = open(conn, context.path)

      assert has_element?(view, "#entry-#{context.diagnosis.id}")
      refute has_element?(view, "#track-details-#{context.diagnosis.id}")
    end
  end

  describe "the page Conditions" do
    setup context do
      clover = resident!(context.lists, context.options, %{name: "Clover", sex: :female})
      admin = [actor: context.administrator, tenant: context.organisation]
      shed = Locations.add_location!(%{name: "Shed B"}, admin)
      {:ok, _placement} = Locations.settle({:resident, context.biscuit.id}, shed.id, admin)

      diagnose!(context, context.bumblefoot, %{onset_on: Date.add(context.today, -3)})
      diagnose!(context, context.uri)

      Journal.write_entry!(
        %{kind: :diagnosis, condition_id: context.uri, resident_id: clover.id},
        context.options
      )

      {:ok, clover: clover, shed: shed}
    end

    test "does not open for a user of another organisation, or with no sign-in", context do
      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)

      assert {:error, {:redirect, %{to: "/"}}} =
               build_conn() |> sign_in(outsider) |> live(context.conditions_path)

      assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), context.conditions_path)
    end

    test "has a link from the list of the residents", context do
      {view, _html} = open(context.conn, context.base)
      assert has_element?(view, "a[href='#{context.conditions_path}']", "Conditions")
    end

    test "counts what the residents have now, by condition and by location", context do
      {view, _html} = open(context.conn, context.conditions_path)

      assert has_element?(
               view,
               "#now-words",
               "3 conditions of 2 residents in care are not resolved."
             )

      assert count(view, "#now-by-condition", "Respiratory infection") == "2"
      assert count(view, "#now-by-condition", "Bumblefoot") == "1"
      assert count(view, "#now-by-location", "Shed B") == "2"
      assert count(view, "#now-by-location", "No place") == "1"

      assert has_element?(
               view,
               "#now-by-location a[href='/o/#{context.organisation.short_name}/housing/#{context.shed.id}']",
               "Shed B"
             )

      # A bar is a drawing that a screen reader does not read.
      assert has_element?(view, "#now-by-condition svg[data-bar][aria-hidden=true]")
    end

    test "says so when no resident has a condition", context do
      for resident <- [context.biscuit, context.clover], episode <- episodes(context, resident) do
        {:ok, _resolved} = Journal.resolve_episode(episode, %{}, context.options)
      end

      {view, _html} = open(context.conn, context.conditions_path)

      assert has_element?(
               view,
               "#now-words",
               "No resident in care has a condition that is not resolved."
             )

      refute has_element?(view, "#now-by-condition")
      refute has_element?(view, "#now-by-location")
    end

    test "counts the conditions that started in each month, for the time and the condition " <>
           "that the member chooses",
         context do
      {view, _html} = open(context.conn, context.conditions_path)

      assert view |> element("#started-by-month") |> render() |> rows() == 6
      assert count(view, "#started-by-condition", "Respiratory infection") == "2"

      html = view |> form("#counts", counts: %{months: "12"}) |> render_change()
      assert html =~ "The last 12 months"
      assert view |> element("#started-by-month") |> render() |> rows() == 12

      view
      |> form("#counts", counts: %{months: "3", condition_id: context.bumblefoot})
      |> render_change()

      assert view |> element("#started-by-month") |> render() |> rows() == 3
      refute has_element?(view, "#started-by-condition")

      total =
        view
        |> element("#started-by-month")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("data")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.to_integer()))
        |> Enum.sum()

      assert total == 1
    end

    test "reads only the values that it knows from the form", context do
      {view, _html} = open(context.conn, context.conditions_path)

      # A time that the form does not offer gives six months, and a condition
      # that is not in the list of the organisation gives each condition.
      render_change(view, "count", %{
        "counts" => %{"months" => "9999", "condition_id" => Ash.UUID.generate()}
      })

      assert view |> element("#started-by-month") |> render() |> rows() == 6
      assert has_element?(view, "#started-by-condition")

      render_change(view, "count", %{"counts" => "text"})
      render_change(view, "count", %{})
      render_click(view, "no_such_event", %{})
      assert view |> element("#started-by-month") |> render() |> rows() == 6
    end

    test "lists each condition of each resident, with a link to its entries", context do
      {view, _html} = open(context.conn, context.conditions_path)
      html = render_async(view)

      [episode] = episodes(context, context.clover)

      assert html =~ "Clover"
      assert html =~ "Biscuit"

      assert has_element?(
               view,
               "a[href='#{context.base}/#{context.clover.id}/journal?episode=#{episode.id}']",
               "Clover"
             )

      assert has_element?(view, "span[data-label=Condition]", "Bumblefoot")
      assert has_element?(view, "span[data-label='Last day']", "Not yet")
    end

    test "reads as the person: a removed resident is in no count and no list", context do
      :ok =
        Rescord.Residents.remove_resident(context.clover,
          actor: context.administrator,
          tenant: context.organisation
        )

      {view, _html} = open(context.conn, context.conditions_path)
      html = render_async(view)

      assert has_element?(
               view,
               "#now-words",
               "2 conditions of 1 resident in care are not resolved."
             )

      refute html =~ "Clover"
    end
  end

  # The number of a row of a list of counts, by the name of the row.
  defp count(view, list, name) do
    view
    |> element("#{list} li", name)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("data")
    |> LazyHTML.text()
  end

  defp rows(html), do: html |> LazyHTML.from_fragment() |> LazyHTML.query("li") |> Enum.count()
end
