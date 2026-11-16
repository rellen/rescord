defmodule Rescord.JournalTest do
  @moduledoc """
  Holds the journal of a resident (`docs/domain.md`, section 5.6, and
  ADR 0030): an entry and the facts of its kind, the time that a thing
  happened, an addendum, and who can correct an entry.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.Journal

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    {_, other} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    options = [actor: member, tenant: organisation]

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     other: other,
     lists: lists,
     options: options,
     biscuit: resident!(lists, options)}
  end

  defp write!(context, attributes) do
    Journal.write_entry!(Map.put(attributes, :resident_id, context.biscuit.id), context.options)
  end

  defp journal(context, extra \\ []) do
    {:ok, entries} = Journal.entries(context.biscuit.id, extra ++ context.options)
    entries
  end

  describe "a journal entry" do
    test "has a kind, the words of its author, and the time of the write", context do
      before = DateTime.utc_now()
      entry = write!(context, %{kind: :behaviour, note: "Popcorning at floor time."})

      assert entry.kind == :behaviour
      assert entry.author_id == context.member.id
      assert DateTime.compare(entry.happened_at, before) != :lt

      assert [%{note: "Popcorning at floor time."}] = journal(context)
    end

    test "of a kind with no facts needs words", context do
      for kind <- [:examination, :placement, :group, :behaviour, :general] do
        assert {:error, %Ash.Error.Invalid{} = error} =
                 Journal.write_entry(
                   %{resident_id: context.biscuit.id, kind: kind},
                   context.options
                 )

        assert Exception.message(error) =~ "is required for an entry of this kind"
      end

      assert journal(context) == []
    end

    test "of a medical kind needs the facts of that kind", context do
      for {kind, facts} <- [
            {:diagnosis, %{}},
            {:measurement, %{measure_kind_id: context.lists.measure_kind.weight}},
            {:measurement, %{value: 1095}},
            {:procedure, %{}},
            {:vaccination, %{}},
            {:prescription, %{dose: "0.2 mL"}}
          ] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Journal.write_entry(
                   Map.merge(%{resident_id: context.biscuit.id, kind: kind, note: "x"}, facts),
                   context.options
                 )
      end

      assert journal(context) == []
    end

    test "holds the facts of each medical kind", context do
      lists = context.lists

      write!(context, %{kind: :diagnosis, condition_id: lists.condition.respiratory_infection})

      write!(context, %{
        kind: :measurement,
        measure_kind_id: lists.measure_kind.weight,
        value: "1095",
        unit_id: lists.unit.g
      })

      write!(context, %{kind: :procedure, procedure_kind_id: lists.procedure_kind.desexing})
      write!(context, %{kind: :vaccination, vaccine: "A sample vaccine"})

      prescription =
        write!(context, %{
          kind: :prescription,
          medication: "A sample antibiotic",
          dose: "0.2 mL two times each day",
          route: :oral,
          starts_on: ~D[2026-11-12],
          ends_on: ~D[2026-11-16]
        })

      {:ok, %{prescription: %{id: prescription_id}}} =
        Journal.entry_with_facts(prescription.id, context.options)

      write!(context, %{kind: :dose, prescription_id: prescription_id, amount: "0.2 mL"})

      by_kind = Map.new(journal(context), &{&1.kind, &1})

      assert to_string(by_kind.diagnosis.diagnosis.condition.label) == "Respiratory infection"
      assert Decimal.equal?(by_kind.measurement.measurement.value, 1095)
      assert to_string(by_kind.measurement.measurement.measure_kind.label) == "Weight"
      assert to_string(by_kind.measurement.measurement.unit.label) == "g"
      assert to_string(by_kind.procedure.procedure.procedure_kind.label) == "Desexing"
      assert by_kind.vaccination.vaccination.vaccine == "A sample vaccine"

      assert %{medication: "A sample antibiotic", route: :oral, ends_on: ~D[2026-11-16]} =
               by_kind.prescription.prescription

      assert by_kind.dose.dose.amount == "0.2 mL"
      assert by_kind.dose.dose.prescription.medication == "A sample antibiotic"
    end

    test "has the time that the member gives, which is not after now", context do
      morning = DateTime.add(DateTime.utc_now(), -3, :hour)

      entry = write!(context, %{kind: :general, note: "Ate well.", happened_at: morning})
      assert DateTime.compare(entry.happened_at, morning) == :eq

      assert {:error, %Ash.Error.Invalid{} = error} =
               Journal.write_entry(
                 %{
                   resident_id: context.biscuit.id,
                   kind: :general,
                   note: "Tomorrow.",
                   happened_at: DateTime.add(DateTime.utc_now(), 1, :hour)
                 },
                 context.options
               )

      assert Exception.message(error) =~ "cannot be after now"
    end

    test "is in the journal in the order of the time that each thing happened", context do
      now = DateTime.utc_now()

      write!(context, %{kind: :general, note: "second", happened_at: DateTime.add(now, -1, :hour)})

      write!(context, %{kind: :general, note: "first", happened_at: DateTime.add(now, -2, :hour)})
      write!(context, %{kind: :vaccination, vaccine: "third"})

      assert Enum.map(journal(context), &(&1.note || &1.vaccination.vaccine)) ==
               ["third", "second", "first"]

      assert [%{kind: :vaccination}] = journal(context, only: :medical)
    end

    test "can add to an earlier entry: an addendum", context do
      first = write!(context, %{kind: :examination, note: "Mild chest sounds."})

      other = [actor: context.other, tenant: context.organisation]

      {:ok, addendum} =
        Journal.write_entry(
          %{
            resident_id: context.biscuit.id,
            kind: :examination,
            note: "Clear on the second check.",
            follows_id: first.id
          },
          other
        )

      {:ok, loaded} = Journal.entry_with_facts(addendum.id, context.options)
      assert loaded.follows.id == first.id
      assert loaded.author_id == context.other.id
    end

    test "is not for a user of another organisation, or for nobody", context do
      outside = organisation!(context.root, "Other")
      {_, outsider} = member!(outside, :administrator, context.root)
      write!(context, %{kind: :general, note: "Ate well."})

      for actor <- [outsider, nil] do
        options = [actor: actor, tenant: context.organisation]

        assert {:ok, []} = Journal.entries(context.biscuit.id, options)

        assert {:error, %Ash.Error.Forbidden{}} =
                 Journal.write_entry(
                   %{resident_id: context.biscuit.id, kind: :general, note: "x"},
                   options
                 )
      end

      assert [_one] = journal(context)
    end

    test "does not take its author as input", context do
      assert {:error, %Ash.Error.Invalid{}} =
               Journal.write_entry(
                 %{
                   resident_id: context.biscuit.id,
                   kind: :general,
                   note: "x",
                   author_id: context.other.id
                 },
                 context.options
               )
    end
  end

  describe "a correction" do
    test "is for the author, an administrator and a root user, and not another member",
         context do
      entry = write!(context, %{kind: :general, note: "Ate wel."})
      before = DateTime.utc_now()

      other = [actor: context.other, tenant: context.organisation]

      assert {:error, %Ash.Error.Forbidden{}} =
               Journal.correct_entry(entry, %{note: "No."}, other)

      for {actor, note} <- [
            {context.member, "Ate well."},
            {context.administrator, "Ate well, with capsicum."},
            {context.root, "Ate well, with a slice of capsicum."}
          ] do
        assert {:ok, %{note: ^note}} =
                 Journal.correct_entry(entry, %{note: note},
                   actor: actor,
                   tenant: context.organisation
                 )
      end

      # The author is still the member who wrote it, and the old words are in the history.
      assert [%{note: "Ate well, with a slice of capsicum.", author_id: author}] =
               journal(context)

      assert author == context.member.id
      assert [%{note: "Ate wel."}] = journal(context, as_of: before)

      assert Journal.can_correct?(:member, context.member, entry)
      refute Journal.can_correct?(:member, context.other, entry)
      assert Journal.can_correct?(:administrator, context.administrator, entry)
      assert Journal.can_correct?(:root, context.root, entry)
      refute Journal.can_correct?(nil, context.other, entry)
    end

    test "changes a fact of the entry, and keeps the old value for a past instant", context do
      entry =
        write!(context, %{
          kind: :measurement,
          measure_kind_id: context.lists.measure_kind.weight,
          value: "1905"
        })

      before = DateTime.utc_now()

      assert {:ok, _} = Journal.correct_entry(entry, %{value: "1095"}, context.options)

      assert [%{measurement: now}] = journal(context)
      assert Decimal.equal?(now.value, 1095)

      assert [%{measurement: then}] = journal(context, as_of: before)
      assert Decimal.equal?(then.value, 1905)
    end
  end

  describe "the measurements of a resident" do
    test "have the newest of each kind", context do
      weight = context.lists.measure_kind.weight
      now = DateTime.utc_now()

      for {value, hours} <- [{"1040", -72}, {"1095", -1}, {"1090", -24}] do
        write!(context, %{
          kind: :measurement,
          measure_kind_id: weight,
          value: value,
          happened_at: DateTime.add(now, hours, :hour)
        })
      end

      write!(context, %{
        kind: :measurement,
        measure_kind_id: context.lists.measure_kind.temperature,
        value: "38.5"
      })

      {:ok, latest} = Journal.latest_measurements(context.biscuit.id, context.options)

      assert Enum.map(
               latest,
               &{to_string(&1.measurement.measure_kind.label),
                Decimal.to_string(&1.measurement.value)}
             ) ==
               [{"Temperature", "38.5"}, {"Weight", "1095"}]
    end
  end

  describe "the grants of the journal" do
    test "name only resources and actions that exist, and give each scope a filter" do
      for {_role, grants} <- Journal.Grants.grants(), {resource, action, scope} <- grants do
        assert Ash.Resource.Info.action(resource, action)
        assert Rescord.Accounts.Grants.filter(resource, scope) != nil
      end

      assert Journal.role_can_write?(:member)
      refute Journal.role_can_write?(nil)
    end
  end
end
