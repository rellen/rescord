defmodule Rescord.EpisodesTest do
  @moduledoc """
  Holds the conditions of a resident (ADR 0083): a diagnosis starts an
  episode or joins the ongoing one, an entry is about an episode of its own
  resident, a member marks an episode as resolved, and the counts of what
  the residents have.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Journal, Lists, Locations, Residents}

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)

    {:ok, bumblefoot} =
      Lists.add_local_value(:condition, "Bumblefoot", actor: root, tenant: organisation)

    options = [actor: member, tenant: organisation]

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     lists: lists,
     uri: lists.condition.respiratory_infection,
     bumblefoot: bumblefoot.id,
     options: options,
     today: Rescord.Accounts.today(organisation),
     biscuit: resident!(lists, options)}
  end

  defp write!(context, attributes) do
    Journal.write_entry!(Map.put(attributes, :resident_id, context.biscuit.id), context.options)
  end

  defp diagnose!(context, condition_id, more \\ %{}) do
    write!(context, Map.merge(%{kind: :diagnosis, condition_id: condition_id}, more))
  end

  defp episodes(context, resident \\ nil) do
    {:ok, episodes} = Journal.episodes_of((resident || context.biscuit).id, context.options)
    episodes
  end

  defp entry(context, id) do
    {:ok, entry} = Journal.entry_with_facts(id, context.options)
    entry
  end

  describe "a diagnosis" do
    test "starts the condition of the resident, on the day of the entry", context do
      diagnosis = diagnose!(context, context.bumblefoot)

      assert [episode] = episodes(context)
      assert episode.condition_id == context.bumblefoot
      assert to_string(episode.condition.label) == "Bumblefoot"
      assert episode.started_on == context.today
      assert episode.ended_on == nil
      assert episode.state == :ongoing
      assert episode.chronic == false
      assert episode.entry_count == 1
      assert diagnosis.episode_id == episode.id
      assert to_string(entry(context, diagnosis.id).episode.condition.label) == "Bumblefoot"
    end

    test "starts it on the day that the member gives, and as chronic", context do
      first = Date.add(context.today, -20)
      diagnose!(context, context.bumblefoot, %{onset_on: first, chronic: true})

      assert [%{started_on: ^first, chronic: true}] = episodes(context)
    end

    test "starts it on the local day of a late entry", context do
      # Three days ago at noon in Brisbane, which is 02:00 in UTC.
      day = Date.add(context.today, -3)
      {:ok, noon} = Rescord.Accounts.local_instant(context.organisation, "#{day}T12:00")
      diagnose!(context, context.uri, %{happened_at: noon})

      assert [%{started_on: ^day}] = episodes(context)
    end

    test "refuses a first day after today, and writes nothing", context do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Journal.write_entry(
                 %{
                   resident_id: context.biscuit.id,
                   kind: :diagnosis,
                   condition_id: context.uri,
                   onset_on: Date.add(context.today, 1)
                 },
                 context.options
               )

      assert Exception.message(error) =~ "cannot be after today"
      assert episodes(context) == []
      assert {:ok, []} = Journal.entries(context.biscuit.id, context.options)
    end

    test "of a condition that the resident has now joins it", context do
      first = diagnose!(context, context.bumblefoot)
      second = diagnose!(context, context.bumblefoot, %{onset_on: Date.add(context.today, -9)})

      assert [episode] = episodes(context)
      assert first.episode_id == episode.id
      assert second.episode_id == episode.id
      assert episode.started_on == context.today
      assert episode.entry_count == 2
    end

    test "of another condition starts another one", context do
      diagnose!(context, context.bumblefoot)
      diagnose!(context, context.uri)

      assert episodes(context) |> Enum.map(& &1.condition_id) |> Enum.sort() ==
               Enum.sort([context.bumblefoot, context.uri])
    end

    test "after the condition was resolved starts a new one", context do
      first = diagnose!(context, context.uri, %{onset_on: Date.add(context.today, -30)})
      [episode] = episodes(context)

      {:ok, _} =
        Journal.resolve_episode(
          episode,
          %{ended_on: Date.add(context.today, -20)},
          context.options
        )

      again = diagnose!(context, context.uri)

      assert [ongoing, resolved] = episodes(context)
      assert ongoing.id == again.episode_id
      assert ongoing.state == :ongoing
      assert resolved.id == first.episode_id
      assert resolved.state == :resolved
    end

    test "of one resident does not join the condition of another", context do
      diagnose!(context, context.uri)
      sage = resident!(context.lists, context.options, %{name: "Sage"})

      Journal.write_entry!(
        %{resident_id: sage.id, kind: :diagnosis, condition_id: context.uri},
        context.options
      )

      assert [%{resident_id: biscuit_id}] = episodes(context)
      assert [%{resident_id: sage_id}] = episodes(context, sage)
      assert biscuit_id == context.biscuit.id
      assert sage_id == sage.id
    end

    test "is not written, with its condition, by a person with no grant", context do
      assert {:error, %Ash.Error.Forbidden{}} =
               Journal.write_entry(
                 %{resident_id: context.biscuit.id, kind: :diagnosis, condition_id: context.uri},
                 actor: nil,
                 tenant: context.organisation
               )

      assert episodes(context) == []
    end
  end

  describe "an entry" do
    setup context do
      diagnosis = diagnose!(context, context.bumblefoot)
      {:ok, episode: hd(episodes(context)), diagnosis: diagnosis}
    end

    test "names a condition of its resident, and the journal filters by it", context do
      about =
        write!(context, %{kind: :general, note: "The pad is dry.", episode_id: context.episode.id})

      write!(context, %{kind: :general, note: "Ate well."})

      assert about.episode_id == context.episode.id

      {:ok, entries} =
        Journal.entries(context.biscuit.id, [episode: context.episode.id] ++ context.options)

      assert entries |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([about.id, context.diagnosis.id])

      {:ok, medical} =
        Journal.entries(
          context.biscuit.id,
          [episode: context.episode.id, only: :medical] ++ context.options
        )

      assert Enum.map(medical, & &1.id) == [context.diagnosis.id]
      assert [%{entry_count: 2}] = episodes(context)
    end

    test "cannot name the condition of another resident", context do
      sage = resident!(context.lists, context.options, %{name: "Sage"})

      assert {:error, %Ash.Error.Invalid{} = error} =
               Journal.write_entry(
                 %{
                   resident_id: sage.id,
                   kind: :general,
                   note: "x",
                   episode_id: context.episode.id
                 },
                 context.options
               )

      assert Exception.message(error) =~ "is not a condition of this resident"
    end

    test "that is a diagnosis cannot name an episode of another condition", context do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Journal.write_entry(
                 %{
                   resident_id: context.biscuit.id,
                   kind: :diagnosis,
                   condition_id: context.uri,
                   episode_id: context.episode.id
                 },
                 context.options
               )

      assert Exception.message(error) =~ "is another condition than the one of the diagnosis"
    end

    test "that adds to an entry is about the condition of that entry", context do
      addendum =
        write!(context, %{
          kind: :diagnosis,
          note: "The vet agrees.",
          follows_id: context.diagnosis.id
        })

      assert addendum.episode_id == context.episode.id
    end

    test "that is a dose is about the condition of its prescription", context do
      prescription =
        write!(context, %{
          kind: :prescription,
          medication: "A sample cream",
          episode_id: context.episode.id
        })

      %{prescription: %{id: prescription_id}} = entry(context, prescription.id)
      dose = write!(context, %{kind: :dose, prescription_id: prescription_id})
      plain = write!(context, %{kind: :dose, amount: "1 drop"})

      assert dose.episode_id == context.episode.id
      assert plain.episode_id == nil
    end

    test "gets a condition, another one, or none with a correction", context do
      note = write!(context, %{kind: :general, note: "Limps a little."})
      assert note.episode_id == nil

      {:ok, about} =
        Journal.correct_entry(note, %{episode_id: context.episode.id}, context.options)

      assert about.episode_id == context.episode.id

      # A correction that does not name the condition keeps it.
      {:ok, kept} = Journal.correct_entry(about, %{note: "Limps a lot."}, context.options)
      assert kept.episode_id == context.episode.id

      {:ok, none} = Journal.correct_entry(kept, %{episode_id: nil}, context.options)
      assert none.episode_id == nil

      sage = resident!(context.lists, context.options, %{name: "Sage"})

      theirs =
        Journal.write_entry!(
          %{resident_id: sage.id, kind: :diagnosis, condition_id: context.uri},
          context.options
        )

      assert {:error, %Ash.Error.Invalid{} = error} =
               Journal.correct_entry(none, %{episode_id: theirs.episode_id}, context.options)

      assert Exception.message(error) =~ "is not a condition of this resident"
    end
  end

  describe "a correction of the condition of a diagnosis" do
    test "gives the episode the new condition, when it is the only diagnosis", context do
      diagnosis = diagnose!(context, context.bumblefoot)

      about =
        write!(context, %{kind: :general, note: "x", episode_id: diagnosis.episode_id})

      {:ok, corrected} =
        Journal.correct_entry(diagnosis, %{condition_id: context.uri}, context.options)

      assert corrected.episode_id == diagnosis.episode_id
      assert [%{condition_id: condition_id, entry_count: 2}] = episodes(context)
      assert condition_id == context.uri
      assert entry(context, about.id).episode_id == diagnosis.episode_id
      assert entry(context, diagnosis.id).diagnosis.condition_id == context.uri
    end

    test "moves the diagnosis, when the episode has another diagnosis", context do
      first = diagnose!(context, context.bumblefoot)
      second = diagnose!(context, context.bumblefoot)
      assert first.episode_id == second.episode_id

      {:ok, corrected} =
        Journal.correct_entry(second, %{condition_id: context.uri}, context.options)

      assert corrected.episode_id != first.episode_id

      by_condition = Map.new(episodes(context), &{&1.condition_id, &1})
      assert by_condition[context.bumblefoot].id == first.episode_id
      assert by_condition[context.uri].id == corrected.episode_id
    end
  end

  describe "a diagnosis from before Rescord had episodes" do
    setup context do
      # Such a diagnosis has no episode: take the one that the write made.
      diagnosis = diagnose!(context, context.uri)
      [episode] = episodes(context)

      :ok =
        Journal.remove_episode(episode,
          actor: context.administrator,
          tenant: context.organisation
        )

      assert episodes(context) == []
      old = entry(context, diagnosis.id)
      assert old.episode_id == nil
      {:ok, old: old}
    end

    test "starts its condition when a member tracks it", context do
      {:ok, tracked} = Journal.track_entry(context.old, context.options)

      assert [episode] = episodes(context)
      assert tracked.episode_id == episode.id
      assert episode.condition_id == context.uri
      assert episode.started_on == context.today

      assert {:error, %Ash.Error.Invalid{} = error} =
               Journal.track_entry(tracked, context.options)

      assert Exception.message(error) =~ "is tracked already"
    end

    test "is the only kind of entry that a member tracks", context do
      note = write!(context, %{kind: :general, note: "Ate well."})

      assert {:error, %Ash.Error.Invalid{} = error} = Journal.track_entry(note, context.options)
      assert Exception.message(error) =~ "is not a diagnosis"
    end
  end

  describe "an episode" do
    setup context do
      diagnose!(context, context.bumblefoot, %{onset_on: Date.add(context.today, -10)})
      {:ok, episode: hd(episodes(context))}
    end

    test "is resolved today, or on the day that the member gives, and opens again", context do
      {:ok, resolved} = Journal.resolve_episode(context.episode, %{}, context.options)
      assert resolved.ended_on == context.today

      {:ok, open} = Journal.reopen_episode(resolved, context.options)
      assert open.ended_on == nil

      day = Date.add(context.today, -2)
      {:ok, resolved} = Journal.resolve_episode(open, %{ended_on: day}, context.options)
      assert resolved.ended_on == day
      assert [%{state: :resolved}] = episodes(context)
    end

    test "has days in their order that are not after today", context do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Journal.resolve_episode(
                 context.episode,
                 %{ended_on: Date.add(context.today, -11)},
                 context.options
               )

      assert Exception.message(error) =~ "cannot be before the first day"

      assert {:error, %Ash.Error.Invalid{} = error} =
               Journal.resolve_episode(
                 context.episode,
                 %{ended_on: Date.add(context.today, 1)},
                 context.options
               )

      assert Exception.message(error) =~ "cannot be after today"

      assert {:error, %Ash.Error.Invalid{}} =
               Journal.revise_episode(
                 context.episode,
                 %{started_on: Date.add(context.today, 1)},
                 context.options
               )
    end

    test "is revised: its days, its mark and its note", context do
      first = Date.add(context.today, -14)

      {:ok, revised} =
        Journal.revise_episode(
          context.episode,
          %{started_on: first, chronic: true, note: "left hind foot"},
          context.options
        )

      assert %{started_on: ^first, chronic: true, note: "left hind foot"} = revised
    end

    test "is removed by an administrator, and its entries stay", context do
      assert {:error, %Ash.Error.Forbidden{}} =
               Journal.remove_episode(context.episode, context.options)

      :ok =
        Journal.remove_episode(context.episode,
          actor: context.administrator,
          tenant: context.organisation
        )

      assert episodes(context) == []

      assert {:ok, [%{kind: :diagnosis, episode: nil, episode_id: nil} = diagnosis]} =
               Journal.entries(context.biscuit.id, context.options)

      # The diagnosis can start the condition again.
      assert {:ok, %{episode_id: id}} = Journal.track_entry(diagnosis, context.options)
      assert [%{id: ^id}] = episodes(context)
    end

    test "is not taken off an entry by a member directly", context do
      {:ok, [diagnosis]} = Journal.entries(context.biscuit.id, context.options)

      for options <- [
            context.options,
            [actor: context.administrator, tenant: context.organisation]
          ] do
        assert {:error, %Ash.Error.Forbidden{}} =
                 diagnosis
                 |> Ash.Changeset.for_update(:release, %{}, options)
                 |> Ash.update()
      end
    end

    test "is not started or renamed by a member directly", context do
      assert {:error, %Ash.Error.Forbidden{}} =
               Journal.Episode
               |> Ash.Changeset.for_create(
                 :start,
                 %{resident_id: context.biscuit.id, condition_id: context.uri},
                 context.options
               )
               |> Ash.create()

      assert {:error, %Ash.Error.Forbidden{}} =
               context.episode
               |> Ash.Changeset.for_update(:rename, %{condition_id: context.uri}, context.options)
               |> Ash.update()
    end

    test "is changed only by a person with the power", context do
      {:ok, reader} =
        Rescord.Accounts.define_role(%{name: "Reader", powers: []},
          actor: context.administrator,
          tenant: context.organisation
        )

      {membership, person} = member!(context.organisation, :member, context.administrator)

      {:ok, _} =
        Rescord.Accounts.set_member_role(membership, reader.id,
          actor: context.administrator,
          tenant: context.organisation
        )

      options = [actor: person, tenant: context.organisation]

      assert {:ok, [_episode]} = Journal.episodes_of(context.biscuit.id, options)

      assert {:error, %Ash.Error.Forbidden{}} =
               Journal.resolve_episode(context.episode, %{}, options)

      assert {:error, %Ash.Error.Forbidden{}} = Journal.reopen_episode(context.episode, options)

      assert {:error, %Ash.Error.Forbidden{}} =
               Journal.revise_episode(context.episode, %{}, options)
    end

    test "of a removed resident is in no list", context do
      :ok =
        Residents.remove_resident(context.biscuit,
          actor: context.administrator,
          tenant: context.organisation
        )

      assert {:ok, []} = Journal.episodes(%{}, context.options)
      assert {:ok, %{conditions: 0}} = Journal.conditions_now(context.options)
    end

    test "is on the timeline when it is resolved and when it opens again", context do
      {:ok, resolved} = Journal.resolve_episode(context.episode, %{}, context.options)
      {:ok, _open} = Journal.reopen_episode(resolved, context.options)

      {:ok, events} = Journal.timeline(context.biscuit.id, context.options)

      assert [
               %{kind: :reopened, condition: "Bumblefoot", user_id: user_id},
               %{kind: :resolved, condition: "Bumblefoot"}
             ] = Enum.filter(events, &(&1.subject == :episode))

      assert user_id == context.member.id
    end
  end

  describe "the counts" do
    test "say what the residents in care have now, by condition and by location", context do
      sage = resident!(context.lists, context.options, %{name: "Sage"})
      fern = resident!(context.lists, context.options, %{name: "Fern"})
      gone = resident!(context.lists, context.options, %{name: "Moss"})

      admin = [actor: context.administrator, tenant: context.organisation]
      {:ok, shed} = Locations.add_location(%{name: "Shed B"}, admin)
      {:ok, _} = Locations.settle({:resident, context.biscuit.id}, shed.id, admin)
      {:ok, _} = Locations.settle({:resident, sage.id}, shed.id, admin)

      diagnose!(context, context.uri)
      diagnose!(context, context.bumblefoot)

      for resident <- [sage, fern, gone] do
        Journal.write_entry!(
          %{resident_id: resident.id, kind: :diagnosis, condition_id: context.uri},
          context.options
        )
      end

      # A resolved condition and the condition of a resident that left are
      # not what the residents have now.
      [fern_episode] = episodes(context, fern)
      {:ok, _} = Journal.resolve_episode(fern_episode, %{}, context.options)

      {:ok, _} =
        Residents.record_departure(
          %{resident_id: gone.id, kind: :release, departed_on: context.today},
          admin
        )

      {:ok, now} = Journal.conditions_now(context.options)

      assert now.conditions == 3
      assert now.residents == 2

      assert [{"Respiratory infection", 2}, {"Bumblefoot", 1}] =
               Enum.map(now.by_condition, &{to_string(&1.condition.label), &1.count})

      assert [{"Shed B", 3}] = Enum.map(now.by_location, &{&1.location.name, &1.count})
    end

    test "count a resident with no place under no location", context do
      diagnose!(context, context.uri)

      {:ok, now} = Journal.conditions_now(context.options)
      assert [%{location: nil, count: 1}] = now.by_location
    end

    test "say how many conditions started in each month", context do
      today = context.today
      last_month = today |> Date.beginning_of_month() |> Date.add(-1)
      long_ago = Date.shift(today, month: -7)

      diagnose!(context, context.bumblefoot)
      diagnose!(context, context.uri, %{onset_on: last_month})

      sage =
        resident!(context.lists, context.options, %{
          name: "Sage",
          arrived_on: Date.shift(today, month: -8)
        })

      Journal.write_entry!(
        %{resident_id: sage.id, kind: :diagnosis, condition_id: context.uri, onset_on: long_ago},
        context.options
      )

      {:ok, started} = Journal.conditions_started(3, [today: today] ++ context.options)

      assert started.total == 2
      assert length(started.by_month) == 3

      assert [
               %{month: this_month, count: 1},
               %{month: month_before, count: 1},
               %{count: 0}
             ] = started.by_month

      assert this_month == Date.beginning_of_month(today)
      assert month_before == Date.beginning_of_month(last_month)

      {:ok, of_uri} =
        Journal.conditions_started(12, [today: today, condition: context.uri] ++ context.options)

      assert of_uri.total == 2
      assert [%{count: 2}] = of_uri.by_condition
      assert Enum.sum(Enum.map(of_uri.by_month, & &1.count)) == 2
    end

    test "count the new cases of each week, and the cases that go on now (ADR 0119)", context do
      today = context.today
      monday = Date.beginning_of_week(today)
      mondays = RescordWeb.Chart.weeks(today, 4)
      diagnose!(context, context.uri)
      diagnose!(context, context.bumblefoot, %{onset_on: Date.add(monday, -7)})

      gone =
        resident!(context.lists, context.options, %{
          name: "Gone",
          arrived_on: Date.add(today, -40)
        })

      old =
        resident!(context.lists, context.options, %{name: "Old", arrived_on: Date.add(today, -90)})

      Journal.write_entry!(
        %{
          resident_id: gone.id,
          kind: :diagnosis,
          condition_id: context.uri,
          onset_on: Date.add(today, -35)
        },
        context.options
      )

      {:ok, _} =
        Residents.record_departure(
          %{resident_id: gone.id, kind: :release, departed_on: today},
          actor: context.administrator,
          tenant: context.organisation
        )

      Journal.write_entry!(
        %{
          resident_id: old.id,
          kind: :diagnosis,
          condition_id: context.uri,
          onset_on: Date.add(today, -80)
        },
        context.options
      )

      [ended] = episodes(context, old)

      {:ok, _} =
        Journal.resolve_episode(ended, %{ended_on: Date.add(today, -60)}, context.options)

      {:ok, counts} = Journal.conditions_by_week(mondays, context.options)

      assert counts.new == 2
      assert counts.ongoing == 2
      assert counts.weeks == [0, 0, 1, 1]

      assert [{"Bumblefoot", [0, 0, 1, 0], 1}, {"Respiratory infection", [0, 0, 0, 1], 1}] =
               Enum.map(counts.conditions, &{to_string(&1.condition.label), &1.weeks, &1.ongoing})

      assert List.last(mondays) == monday
    end
  end
end
