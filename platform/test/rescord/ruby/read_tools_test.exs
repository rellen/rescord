defmodule Rescord.Ruby.ReadToolsTest do
  @moduledoc """
  Holds the tools of the assistant about a resident, its journal and the
  housing (ADR 0069): `resident_profile`, `resident_timeline`, `housing`
  and `find_locations`, each through the loop of `AshAi` with the options
  of `Rescord.Ruby.Toolbox`, as a reply runs them.

  For each tool: what a member gets, that it names no member, the words of
  a wrong argument, and nothing for a person who is no member or in
  another organisation.

  The model answers from a script. No test calls a provider.

  The test creates an organisation, so it does not run beside others.
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.RubyFixtures

  alias Rescord.{Accounts, Journal, Locations, Residents, Ruby}
  alias Rescord.Ruby.{ScriptedModel, Toolbox}
  alias Rescord.Ruby.LLM.Client

  @zone "Australia/Brisbane"

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {:ok, organisation} = Accounts.set_organisation_time_zone(organisation, @zone, actor: root)
    {_, administrator} = member!(organisation, :administrator, root)
    admin = [actor: administrator, tenant: organisation]
    {_, member} = member!(organisation, :member, administrator)
    options = [actor: member, tenant: organisation]

    lists = lists!(organisation, root)
    biscuit = resident!(lists, admin, %{markings: "A white blaze", born_on: ~D[2024-03-01]})
    clover = resident!(lists, admin, %{name: "Clover", sex: :female})

    {:ok, profile} = Ruby.LLM.profile_of(provider!(root))

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     admin: admin,
     member: member,
     options: options,
     lists: lists,
     biscuit: biscuit,
     clover: clover,
     profile: profile}
  end

  # Runs one tool call as the loop does for this person in this tenant, and
  # gives what the model reads: the text of the tool result.
  defp call(context, user, tenant, name, arguments) do
    ScriptedModel.script([{:tool, name, arguments}, {:text, "Read."}])

    assert {:ok, %{final_text: "Read."}} =
             AshAi.ToolLoop.run(
               [ReqLLM.Context.user("A question")],
               Toolbox.options(user, tenant, context.profile)
             )

    Client.take_requests()

    [_question, answer] = ScriptedModel.requests()
    %{role: :tool, content: [%{type: :text, text: text}]} = List.last(answer.messages)
    text
  end

  defp call(context, name, arguments),
    do: call(context, context.member, context.organisation, name, arguments)

  defp decoded(context, name, arguments), do: Jason.decode!(call(context, name, arguments))

  defp write!(context, resident, attributes, options \\ nil) do
    Journal.write_entry!(
      Map.put(attributes, :resident_id, resident.id),
      options || context.options
    )
  end

  # Each person who must get nothing: a user who is no member, a root user
  # who is no member, and a member in another organisation.
  defp outsiders(context) do
    other = organisation!(context.root, "Banksia Rise")

    [
      {user!(), context.organisation},
      {context.root, context.organisation},
      {context.member, other}
    ]
  end

  # Nothing of a member is in a result: no id and no address.
  defp refute_members(context, text) do
    for user <- [context.member, context.administrator] do
      refute text =~ user.id
      refute text =~ to_string(user.email)
    end
  end

  describe "the toolbox" do
    test "gives a member the tools of the resident, the journal and the housing", context do
      options = Toolbox.options(context.member, context.organisation, context.profile)

      assert :find_locations in options[:tools]

      names = for {%ReqLLM.Tool{name: name}, _run} <- options[:extra_tools], do: name
      assert ["tasks_for_day", "resident_profile", "resident_timeline", "housing"] == names
    end

    test "gives a person who is no member none of them", context do
      for user <- [context.root, user!()] do
        assert Toolbox.options(user, context.organisation, context.profile)[:extra_tools] == []
      end
    end
  end

  describe "resident_profile" do
    setup context do
      barn = Locations.add_location!(%{name: "Barn", capacity: 10}, context.admin)
      pen = Locations.add_location!(%{name: "Pen 2", parent_id: barn.id}, context.admin)
      Locations.place!(%{location_id: pen.id, resident_id: context.biscuit.id}, context.admin)

      Residents.record_parent!(
        %{resident_id: context.biscuit.id, parent_id: context.clover.id, role: :mother},
        context.admin
      )

      today = Accounts.today(context.organisation)
      weight = context.lists.measure_kind.weight

      write!(context, context.biscuit, %{
        kind: :measurement,
        measure_kind_id: weight,
        value: "1040",
        unit_id: context.lists.unit.g,
        happened_at: DateTime.add(DateTime.utc_now(), -10, :day)
      })

      write!(context, context.biscuit, %{
        kind: :measurement,
        measure_kind_id: weight,
        value: "1095",
        unit_id: context.lists.unit.g
      })

      write!(context, context.biscuit, %{
        kind: :prescription,
        medication: "A sample antibiotic",
        dose: "0.2 mL two times each day",
        route: :oral,
        starts_on: Date.add(today, -2),
        ends_on: Date.add(today, 5)
      })

      write!(context, context.biscuit, %{
        kind: :prescription,
        medication: "An old cream",
        dose: "A thin layer",
        route: :topical,
        starts_on: Date.add(today, -30),
        ends_on: Date.add(today, -20)
      })

      {:ok, pen: pen, today: today}
    end

    test "gives a member who the resident is, where it lives and what runs today", context do
      json = call(context, "resident_profile", %{"resident" => context.biscuit.id})
      profile = Jason.decode!(json)

      assert profile["ref"] == "resident:" <> context.biscuit.id
      assert profile["label"] == "Biscuit"
      assert profile["species"] == "Guinea pig"
      assert profile["sex"] == "male"
      assert profile["status"] == "in care"
      assert profile["born_on"] == "2024-03-01"
      assert profile["markings_text"] == "A white blaze"
      assert profile["arrival"]["kind"] == "surrender"
      assert profile["today"] == Date.to_iso8601(context.today)

      assert [%{"ref" => "location:" <> pen_id, "label" => "Pen 2", "path" => "Barn > Pen 2"}] =
               profile["home"]

      assert pen_id == context.pen.id

      assert [%{"label" => "Clover", "role" => "mother"}] = profile["relations"]["parents"]

      # The newest measurement of each kind, with its day.
      assert [%{"label" => "Weight", "value" => "1095 g", "ref" => "entry:" <> _id}] =
               profile["measurements"]

      # Only the prescription whose days hold today, as it was written.
      assert [prescription] = profile["prescriptions"]
      assert prescription["medication_text"] == "A sample antibiotic"
      assert prescription["dose_text"] == "0.2 mL two times each day"
      assert prescription["route"] == "oral"
      refute json =~ "An old cream"

      refute_members(context, json)
    end

    test "takes a name in any case, and lists the residents of a name that two have", context do
      assert decoded(context, "resident_profile", %{"resident" => "biscuit"})["label"] ==
               "Biscuit"

      resident!(context.lists, context.admin, %{name: "Clover", sex: :male})

      assert %{"choose" => choices} =
               decoded(context, "resident_profile", %{"resident" => "Clover"})

      assert length(choices) == 2
      assert Enum.all?(choices, &(&1["label"] == "Clover" and &1["ref"] =~ "resident:"))

      # A part of a name finds the one resident that has it.
      assert decoded(context, "resident_profile", %{"resident" => "bisc"})["label"] == "Biscuit"
    end

    test "takes the ref of another result, an id in capitals, and a name of 16 bytes", context do
      id = context.biscuit.id

      for value <- ["resident:" <> id, String.upcase(id), " #{id} "] do
        assert decoded(context, "resident_profile", %{"resident" => value})["label"] == "Biscuit"
      end

      # `Ecto.UUID.cast/1` takes any text of 16 bytes as an id. A name is no id.
      resident!(context.lists, context.admin, %{name: "Biscuit and Jack"})
      assert byte_size("Biscuit and Jack") == 16

      assert decoded(context, "resident_profile", %{"resident" => "Biscuit and Jack"})["label"] ==
               "Biscuit and Jack"
    end

    test "lists at most 10 residents of a name, in the order of the names, and says how many more",
         context do
      for n <- 1..11, do: resident!(context.lists, context.admin, %{name: "Pip #{n}"})

      assert %{"choose" => choices, "more_choices" => 1} =
               decoded(context, "resident_profile", %{"resident" => "pip"})

      labels = Enum.map(choices, & &1["label"])
      assert length(labels) == 10
      assert labels == Enum.sort_by(labels, &String.downcase/1)
    end

    test "answers a resident that is not there, and a wrong argument, in words", context do
      assert call(context, "resident_profile", %{"resident" => "   "}) =~
               "give the id or the name"

      assert call(context, "resident_profile", %{"resident" => "Mango"}) =~
               "hold no resident with that name"

      assert call(context, "resident_profile", %{"resident" => Ash.UUID.generate()}) =~
               "hold no resident with this id"

      assert call(context, "resident_profile", %{}) =~ "give the id or the name"
      assert call(context, "resident_profile", %{"resident" => 7}) =~ "give the id or the name"
    end

    test "gives nothing to a person who is no member, and nothing elsewhere", context do
      for {user, tenant} <- outsiders(context) do
        text =
          call(context, user, tenant, "resident_profile", %{"resident" => context.biscuit.id})

        refute text =~ "Biscuit"
        refute text =~ "antibiotic"
      end
    end

    test "runs with the name of the schema as the tenant, as a job has it", context do
      run = Ruby.Digests.ResidentProfile

      assert {:ok, json} =
               run.run(%{"resident" => "Biscuit"}, %{
                 actor: Ruby.Actor.for(context.member),
                 tenant: "org_" <> context.organisation.id
               })

      assert Jason.decode!(json)["label"] == "Biscuit"
    end
  end

  describe "resident_timeline" do
    setup context do
      now = DateTime.utc_now()

      write!(context, context.biscuit, %{
        kind: :behaviour,
        note: "Popcorning at floor time.",
        happened_at: DateTime.add(now, -3, :day)
      })

      write!(
        context,
        context.biscuit,
        %{
          kind: :vaccination,
          vaccine: "A sample vaccine",
          happened_at: DateTime.add(now, -2, :day)
        },
        context.admin
      )

      write!(context, context.biscuit, %{
        kind: :measurement,
        measure_kind_id: context.lists.measure_kind.weight,
        value: "1095",
        unit_id: context.lists.unit.g,
        happened_at: DateTime.add(now, -1, :day)
      })

      :ok
    end

    test "gives the journal and the changes, the newest first, and who wrote each", context do
      json = call(context, "resident_timeline", %{"resident" => "Biscuit"})
      timeline = Jason.decode!(json)

      assert timeline["label"] == "Biscuit"
      assert timeline["more"] == 0

      # The changes that Rescord recorded are there too: the resident was
      # registered now, after the entries of the days before.
      kinds = Enum.map(timeline["events"], & &1["kind"])

      assert kinds ==
               ["arrival started", "name started", "measurement", "vaccination", "behaviour"]

      [arrival, _name, weight, vaccine, note] = timeline["events"]
      assert arrival["arrival"] == "surrender"
      assert arrival["by"] == "another member"
      assert weight["measure"] == "Weight"
      assert weight["value"] == "1095 g"
      assert weight["by"] == "you"
      assert vaccine["vaccine_text"] == "A sample vaccine"
      assert vaccine["by"] == "another member"
      assert note["note_text"] == "Popcorning at floor time."

      refute_members(context, json)
    end

    test "keeps the medical history, the other entries, a day on, and a number", context do
      medical =
        decoded(context, "resident_timeline", %{"resident" => "Biscuit", "kinds" => "medical"})

      assert Enum.map(medical["events"], & &1["kind"]) == ["measurement", "vaccination"]

      daily =
        decoded(context, "resident_timeline", %{"resident" => "Biscuit", "kinds" => "daily"})

      assert Enum.map(daily["events"], & &1["kind"]) == ["behaviour"]

      yesterday = Date.to_iso8601(Date.add(Accounts.today(context.organisation), -1))

      since =
        decoded(context, "resident_timeline", %{
          "resident" => "Biscuit",
          "kinds" => "medical",
          "since" => yesterday
        })

      assert Enum.map(since["events"], & &1["kind"]) == ["measurement"]

      # By id and by ref, as another tool gives them: the same events.
      for value <- [context.biscuit.id, "resident:" <> context.biscuit.id] do
        by_id = decoded(context, "resident_timeline", %{"resident" => value})
        assert by_id["label"] == "Biscuit"

        assert by_id["events"] ==
                 decoded(context, "resident_timeline", %{"resident" => "Biscuit"})["events"]
      end

      one = decoded(context, "resident_timeline", %{"resident" => "Biscuit", "limit" => 1})
      assert length(one["events"]) == 1
      assert one["more"] > 1
    end

    test "answers a wrong argument in words", context do
      for {arguments, words} <- [
            {%{"resident" => "Biscuit", "kinds" => "some"}, "kinds: give one of"},
            {%{"resident" => "Biscuit", "since" => "Tuesday"}, "since: give a date"},
            {%{"resident" => "Biscuit", "limit" => 41}, "limit: give a whole number"},
            {%{}, "give the id or the name"}
          ] do
        assert call(context, "resident_timeline", arguments) =~ words
      end
    end

    test "gives nothing to a person who is no member, and nothing elsewhere", context do
      for {user, tenant} <- outsiders(context) do
        text =
          call(context, user, tenant, "resident_timeline", %{"resident" => context.biscuit.id})

        refute text =~ "Popcorning"
        refute text =~ "Biscuit"
      end
    end
  end

  describe "housing" do
    setup context do
      barn = Locations.add_location!(%{name: "Barn", capacity: 1}, context.admin)
      pen = Locations.add_location!(%{name: "Pen 2", parent_id: barn.id}, context.admin)
      shed = Locations.add_location!(%{name: "Feed shed"}, context.admin)
      Locations.place!(%{location_id: pen.id, resident_id: context.biscuit.id}, context.admin)

      pair =
        Residents.form_group!(
          %{name: "The pair", resident_ids: [context.clover.id]},
          context.admin
        )

      Locations.place!(%{location_id: barn.id, group_id: pair.id}, context.admin)

      {:ok, barn: barn, pen: pen, shed: shed, pair: pair}
    end

    test "gives the tree of the places, with the counts and the capacity", context do
      json = call(context, "housing", %{})
      %{"places" => places} = Jason.decode!(json)

      assert Enum.map(places, & &1["label"]) == ["Barn", "Feed shed"]
      [barn, shed] = places

      assert barn["capacity"] == 1
      assert barn["count"] == 2
      assert barn["over_capacity"] == true
      assert [%{"label" => "Pen 2", "count" => 1}] = barn["inside"]
      refute Map.has_key?(shed, "count")
      refute Map.has_key?(shed, "over_capacity")

      refute_members(context, json)
    end

    test "gives one place by its name, with its path and who lives there", context do
      pen = decoded(context, "housing", %{"location" => "pen 2"})

      assert pen["path"] == "Barn > Pen 2"
      assert [%{"label" => "Biscuit", "ref" => "resident:" <> _id}] = pen["residents"]

      barn = decoded(context, "housing", %{"location" => context.barn.id})
      assert [%{"label" => "The pair", "residents" => [%{"label" => "Clover"}]}] = barn["groups"]

      assert call(context, "housing", %{"location" => "Paddock"}) =~
               "hold no location with that name"
    end

    test "gives nothing to a person who is no member, and nothing elsewhere", context do
      for {user, tenant} <- outsiders(context) do
        text = call(context, user, tenant, "housing", %{})
        refute text =~ "Barn"
      end
    end
  end

  describe "find_locations" do
    setup context do
      Locations.add_location!(%{name: "Barn", capacity: 10}, context.admin)
      Locations.add_location!(%{name: "Feed shed"}, context.admin)
      :ok
    end

    test "finds the places by name, with the fields of the tool and no other", context do
      json =
        call(context, "find_locations", %{
          "filter" => %{"name" => %{"contains" => "Barn"}}
        })

      assert %{"results" => [barn]} = Jason.decode!(json)
      assert barn["name"] == "Barn"
      assert barn["capacity"] == 10
      assert Map.keys(barn) |> Enum.sort() == ["capacity", "id", "name"]
    end

    test "gives nothing to a person who is no member, and nothing elsewhere", context do
      for {user, tenant} <- outsiders(context) do
        refute call(context, user, tenant, "find_locations", %{}) =~ "Barn"
      end
    end
  end
end
