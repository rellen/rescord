defmodule RescordWeb.ReportWordsTest do
  @moduledoc """
  Holds the words of the reports (ADR 0076): `RescordWeb.ReportWords` turns
  the facts of each report of the refuge Wattle Creek into the text that
  its template shows.

  The test creates an organisation, so it does not run beside others (see
  `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.StorageFixtures

  alias Rescord.Reports.Facts
  alias RescordWeb.{ReportWords, ResidentWords}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    disk_store!(tmp_dir)
    {:ok, Rescord.ReportsFixtures.refuge!()}
  end

  # The data of a report as its template gets it.
  defp data(context, report, arguments \\ %{}) do
    now = DateTime.utc_now()
    {:ok, facts} = Facts.read(report, arguments, context.options, now)

    ReportWords.data(
      report,
      facts
      |> Map.delete(:files)
      |> Map.merge(%{organisation: context.organisation, made_at: now})
    )
  end

  defp value(rows, label), do: Enum.find_value(rows, &(&1.label == label && &1.value))
  defp date(context, days_ago), do: ResidentWords.date(Date.add(context.today, -days_ago))

  test "the module of the configuration words each report", context do
    assert Rescord.Reports.Wording.module() == ReportWords
    assert Enum.sort(ReportWords.reports()) == Enum.sort(Rescord.Reports.reports())

    frame = data(context, :housing).frame
    assert frame.organisation == "Wattle Creek"
    assert frame.title == "Housing"
    assert frame.made =~ ~r/^Made on \d{1,2} \w+ \d{4}, \d{1,2}:\d\d (am|pm)$/
    assert %NaiveDateTime{} = frame.date
  end

  test "a report has the dates of the locale of its organisation", context do
    assert RescordWeb.Locale.current() == "en-AU"
    assert data(context, :housing).frame.subtitle =~ ~r/^Who lives where on \d{1,2} \w+ \d{4}$/

    american = %{context | organisation: %{context.organisation | locale: "en-US"}}
    assert data(american, :housing).frame.subtitle =~ ~r/^Who lives where on \w+ \d{1,2}, \d{4}$/
    assert data(american, :housing).frame.made =~ ~r/ (AM|PM)$/

    # The words leave the locale of the process as it was.
    assert RescordWeb.Locale.current() == "en-AU"
  end

  test "the record of a resident", context do
    arguments = %{resident_id: context.residents.biscuit.id, journal: :all, photos: true}
    record = data(context, :resident_record, arguments)

    assert record.frame.title == "Record of Biscuit"
    assert record.frame.subtitle == "With its journal and its photos"
    assert record.name == "Biscuit"
    assert record.status == "In care"
    assert record.photo == "photos/profile.webp"
    assert value(record.about, "Species") == "Guinea pig"
    assert value(record.about, "Desex status") == "Desexed"
    assert value(record.about, "Colour") == "Tan, White"
    assert value(record.stay, "Lives in") == "Main shed › Pen 3"
    assert value(record.stay, "Arrival") == "Surrender by an owner, #{date(context, 64)}"
    assert value(record.relations, "Group") == "Biscuit and Pepper"
    assert %{kind: "Ear tag", value: "WC-041"} in record.identifiers
    assert [%{words: "Weight: 950 g"}] = record.measurements
    assert record.journal.title == "Journal"
    assert "Behaviour" in Enum.map(record.journal.entries, & &1.kind)
    assert length(record.photos) == 3
    assert "After the desexing" in Enum.map(record.photos, & &1.caption)
    assert record.more_photos == nil

    medical = data(context, :resident_record, %{arguments | journal: :medical, photos: false})
    assert medical.frame.subtitle == "With its medical history"
    assert medical.journal.title == "Medical history"
    refute "Behaviour" in Enum.map(medical.journal.entries, & &1.kind)
    assert length(medical.journal.entries) < length(record.journal.entries)
    assert medical.photos == []

    plain = data(context, :resident_record, %{arguments | journal: :none, photos: false})
    assert plain.frame.subtitle == nil
    assert plain.journal == nil
  end

  test "the cage card", context do
    card = data(context, :cage_card, %{resident_id: context.residents.biscuit.id})

    assert card.frame.title == "Cage card of Biscuit"
    assert card.species == "Guinea pig"
    assert card.away == nil
    assert value(card.about, "Lives in") == "Main shed › Pen 3"
    assert card.measurements == ["Weight: 950 g"]

    assert [%{title: "Feed hay and pellets", when: "Each day at 8:00 am and 5:30 pm"}] =
             card.routines

    away = data(context, :cage_card, %{resident_id: context.residents.juniper.id})
    assert away.status == "Away for a time"
    assert is_binary(away.away)
    assert away.photo == nil
    assert away.routines == []
  end

  test "the register", context do
    register = data(context, :register)

    assert register.frame.subtitle == "The residents in care today, #{date(context, 0)}"

    assert register.counts == [
             %{label: "Residents", value: "7"},
             %{label: "Guinea pig", value: "5"},
             %{label: "Rabbit", value: "2"},
             %{label: "Away for a time", value: "1"}
           ]

    assert Enum.map(register.rows, & &1.name) ==
             ~w(Biscuit Clover Hazel Juniper Pepper Pip Squeak)

    biscuit = hd(register.rows)
    assert biscuit.identifiers == ["Ear tag: WC-041", "Microchip: 956000012345678"]
    assert biscuit.sex == "Male, desexed"
    assert biscuit.arrived == "#{date(context, 64)}, surrender by an owner"
    assert biscuit.place == "Main shed › Pen 3"

    juniper = Enum.find(register.rows, &(&1.name == "Juniper"))
    assert juniper.status == "Away for a time"
    assert juniper.born == nil

    past = data(context, :register, %{on: Date.add(context.today, -15)})
    assert past.frame.subtitle == "The residents in care at the end of #{date(context, 15)}"
  end

  test "the arrivals and the departures", context do
    movements =
      data(context, :movements, %{from: Date.add(context.today, -90), to: context.today})

    assert movements.frame.subtitle == "From #{date(context, 90)} to #{date(context, 0)}"

    assert movements.summary == [
             %{label: "In care at the start", value: "0"},
             %{label: "Arrivals", value: "8"},
             %{label: "Departures", value: "1"},
             %{label: "In care at the end", value: "7"}
           ]

    assert hd(movements.arrivals_by_kind) == %{label: "Surrender by an owner", value: "3"}

    assert movements.arrivals_by_species == [
             %{label: "Guinea pig", value: "6"},
             %{label: "Rabbit", value: "2"}
           ]

    assert Enum.map(movements.arrivals, & &1.name) ==
             ~w(Maple Biscuit Pepper Hazel Clover Pip Squeak Juniper)

    assert [maple] = movements.departures
    assert maple.kind == "Transfer to another organisation"
    assert maple.stay == "74 days"
    assert maple.date == date(context, 6)
  end

  test "the tasks of the day", context do
    sheet = data(context, :task_sheet)

    assert sheet.frame.title == "Tasks of the day"
    assert [%{title: "Trim the nails of Biscuit", done: false}] = sheet.late

    assert Enum.map(sheet.tasks, & &1.title) == [
             "Check the water bottles",
             "Feed hay and pellets",
             "Give Doxycycline",
             "Collect Juniper from the vet",
             "Lock the shed"
           ]

    assert %{done: true, state: "Done", kind: "Clean"} = hd(sheet.tasks)
    dose = Enum.find(sheet.tasks, &(&1.title == "Give Doxycycline"))
    assert dose.who == "mel@example.org"
    assert dose[:for] == "Biscuit"
    assert Enum.find(sheet.tasks, &(&1.title == "Lock the shed")).who == "Anybody"

    tomorrow = data(context, :task_sheet, %{on: Date.add(context.today, 1)})
    assert tomorrow.late == []

    assert Enum.map(tomorrow.tasks, & &1.title) == [
             "Feed hay and pellets",
             "Feed hay and pellets"
           ]
  end

  test "the stock", context do
    stock = data(context, :stock)

    assert Enum.map(stock.attention, &{&1.item, &1.words}) == [
             {"Doxycycline 50 mg/ml", "Has stock past its expiry date"},
             {"Guinea pig pellets", "Has stock that expires soon"},
             {"Meadow hay", "Order more"}
           ]

    assert Enum.map(stock.categories, & &1.name) == ["Bedding", "Food", "Medication"]

    [%{items: [liners]}, %{items: [pellets, hay]}, _medication] = stock.categories
    assert %{name: "Fleece liners", level: "0", states: "None in stock", lots: []} = liners
    assert %{level: "14 kg", reorder: "5 kg"} = pellets

    assert [%{name: "Lot P-61", state: "Expires soon"}, %{name: "Lot P-77", state: nil}] =
             pellets.lots

    assert [%{expires: "No expiry date", places: [%{place: "Main shed"}]}] = hay.lots
  end

  test "the housing", context do
    housing = data(context, :housing)

    assert housing.total == "6 residents in 6 locations"

    assert Enum.map(housing.rows, &{&1.depth, &1.name, &1.count}) == [
             {0, "Main shed", "5 of 12"},
             {1, "Pen 1", "3 of 2"},
             {1, "Pen 2", "0 of 2"},
             {1, "Pen 3", "2 of 4"},
             {0, "Quarantine cottage", "1"},
             {1, "Isolation room", "1 of 1"}
           ]

    pen_1 = Enum.find(housing.rows, &(&1.name == "Pen 1"))
    assert pen_1.over
    assert pen_1.residents == ~w(Hazel Pip Squeak)

    pen_3 = Enum.find(housing.rows, &(&1.name == "Pen 3"))
    assert pen_3.groups == [%{name: "Biscuit and Pepper", members: ~w(Biscuit Pepper)}]
    assert housing.unplaced == ["Clover"]
  end
end
