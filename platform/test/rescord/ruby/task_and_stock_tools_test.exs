defmodule Rescord.Ruby.TaskAndStockToolsTest do
  @moduledoc """
  Holds the tools of the assistant about the late tasks and the inventory
  (ADR 0069): `overdue_tasks`, `stock_levels` and `find_items`, each
  through the loop of `AshAi` with the options of `Rescord.Ruby.Toolbox`,
  as a reply runs them.

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

  alias Rescord.{Accounts, Inventory, Locations, Ruby, Tasks}
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
    {:ok, profile} = Ruby.LLM.profile_of(provider!(root))

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     admin: admin,
     member: member,
     options: options,
     lists: lists,
     today: Accounts.today(organisation),
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

  defp refute_members(context, text) do
    for user <- [context.member, context.administrator] do
      refute text =~ user.id
      refute text =~ to_string(user.email)
    end
  end

  test "gives a member the tools of the late tasks and the stock", context do
    options = Toolbox.options(context.member, context.organisation, context.profile)
    names = Enum.map(options[:extra_tools], fn {tool, _run} -> tool.name end)

    assert "overdue_tasks" in names
    assert "stock_levels" in names
    assert :find_items in options[:tools]
  end

  describe "overdue_tasks" do
    setup context do
      now = DateTime.utc_now()

      plan = fn title, hours, values ->
        %{
          title: title,
          due_at: DateTime.add(now, hours, :hour),
          kind_id: context.lists.task_kind.feed
        }
        |> Map.merge(values)
        |> Tasks.plan_task!(context.admin)
      end

      plan.("Check the fence", -30, %{note: "The gate by the road."})
      plan.("Feed the goats", -2, %{})
      plan.("Weigh Clover", 3, %{})
      done = plan.("Muck out", -5, %{})
      Tasks.complete_task!(done, %{}, context.admin)
      skipped = plan.("Brush Pepper", -4, %{})
      Tasks.skip_task!(skipped, %{skip_reason: "Too wet"}, context.admin)
      :ok
    end

    test "lists the tasks that are late, the oldest first, and names no member", context do
      json = call(context, "overdue_tasks", %{})
      result = Jason.decode!(json)

      assert result["count"] == 2
      assert Enum.map(result["tasks"], & &1["label"]) == ["Check the fence", "Feed the goats"]
      assert Enum.all?(result["tasks"], &(&1["state"] == "overdue" and &1["ref"] =~ "task:"))
      assert hd(result["tasks"])["note_text"] == "The gate by the road."
      assert result["now"] =~ ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/
      assert result["more"] == 0

      refute json =~ "Muck out"
      refute json =~ "Brush Pepper"
      refute json =~ "Weigh Clover"
      refute_members(context, json)
    end

    test "gives nothing to a person who is no member, and nothing elsewhere", context do
      for {user, tenant} <- outsiders(context) do
        refute call(context, user, tenant, "overdue_tasks", %{}) =~ "fence"
      end
    end
  end

  describe "the stock" do
    setup context do
      shed = Locations.add_location!(%{name: "Feed shed"}, context.admin)
      clinic = Locations.add_location!(%{name: "Clinic room"}, context.admin)

      item = fn name, category, unit, reorder ->
        Inventory.add_item!(
          %{
            name: name,
            category_id: category,
            unit_id: unit,
            reorder_level: reorder,
            note: "Ask the member who orders it"
          },
          context.admin
        )
      end

      hay = item.("Meadow hay", context.lists.item_category.food, context.lists.unit.bag, 10)
      drops = item.("Eye drops", context.lists.item_category.medication, nil, nil)
      straw = item.("Straw", context.lists.item_category.bedding, context.lists.unit.bag, nil)

      lot = fn item, facts ->
        %{item_id: item.id, quantity: 4, location_id: shed.id}
        |> Map.merge(facts)
        |> Inventory.receive_lot!(context.options)
      end

      lot.(hay, %{code: "H-1"})
      # An old lot with nothing left, which expired: the page counts it alone.
      old = lot.(hay, %{code: "H-0", quantity: 2, expires_on: Date.add(context.today, -60)})

      {:ok, _} =
        Inventory.use_stock(
          %{lot_id: old.id, location_id: shed.id, quantity: 2},
          context.options
        )

      lot.(drops, %{code: "D-7", location_id: clinic.id, expires_on: Date.add(context.today, 5)})
      lot.(drops, %{code: "D-2", location_id: clinic.id, expires_on: Date.add(context.today, -3)})
      straw_lot = lot.(straw, %{quantity: 1})

      {:ok, _} =
        Inventory.use_stock(
          %{lot_id: straw_lot.id, location_id: clinic.id, quantity: 2},
          context.options
        )

      {:ok, shed: shed, clinic: clinic, hay: hay, drops: drops, straw: straw}
    end

    test "gives each item with its level and what is wrong with it", context do
      json = call(context, "stock_levels", %{})
      items = Map.new(Jason.decode!(json)["items"], &{&1["label"], &1})

      assert Map.keys(items) |> Enum.sort() == ["Eye drops", "Meadow hay", "Straw"]

      hay = items["Meadow hay"]
      assert hay["ref"] == "item:" <> context.hay.id
      assert hay["level"] == "4 bag"
      assert hay["reorder_level"] == "10 bag"
      assert hay["faults"] == ["below the reorder level"]
      assert [%{"label" => "Lot H-1", "places" => [%{"place" => "Feed shed"}]}] = hay["lots"]
      assert hay["lots_with_nothing_left"] == 1
      refute Map.has_key?(hay, "expired")

      assert [
               %{
                 "place" => "the whole organisation",
                 "wanted" => "10 bag",
                 "good_to_use" => "4 bag"
               }
             ] =
               hay["short"]

      drops = items["Eye drops"]
      assert drops["level"] == "8"
      assert drops["expired"] == "4"
      assert drops["expires_soon"] == "4"

      # The lot that expires first is first.
      assert [
               %{"label" => "Lot D-2", "expiry" => "past its expiry date"},
               %{"label" => "Lot D-7"}
             ] =
               drops["lots"]

      assert [%{"place" => "Clinic room", "level" => "4"}] = hd(drops["lots"])["places"]

      straw = items["Straw"]
      assert [%{"place" => "Clinic room", "level" => "-2 bag"}] = straw["below_zero"]

      refute json =~ "Ask the member"
      refute_members(context, json)
    end

    test "keeps the items of one fault", context do
      labels = fn only ->
        decoded(context, "stock_levels", %{"only" => only})["items"] |> Enum.map(& &1["label"])
      end

      assert labels.("short") == ["Meadow hay"]
      assert labels.("expiring") == ["Eye drops"]
      assert labels.("below_zero") == ["Straw"]
      assert labels.("all") == ["Eye drops", "Meadow hay", "Straw"]
    end

    test "gives one item by name, by id or by ref, and the choices of a name", context do
      for value <- ["meadow", context.hay.id, "item:" <> context.hay.id] do
        assert [%{"label" => "Meadow hay"}] =
                 decoded(context, "stock_levels", %{"item" => value})["items"]
      end

      Inventory.add_item!(
        %{name: "Meadow hay, small bales", category_id: context.lists.item_category.food},
        context.admin
      )

      # The same name wins over a name that holds it.
      assert [%{"label" => "Meadow hay"}] =
               decoded(context, "stock_levels", %{"item" => "Meadow hay"})["items"]

      assert %{"choose" => choices} = decoded(context, "stock_levels", %{"item" => "meadow"})
      assert Enum.map(choices, & &1["label"]) == ["Meadow hay", "Meadow hay, small bales"]
    end

    test "answers a wrong argument in words", context do
      assert call(context, "stock_levels", %{"item" => "Carrots"}) =~
               "hold no item with that name"

      assert call(context, "stock_levels", %{"item" => Ash.UUID.generate()}) =~
               "hold no item with this id"

      assert call(context, "stock_levels", %{"only" => "cheap"}) =~ "only: give one of"
    end

    test "finds the items by name, with the id and the name alone", context do
      json = call(context, "find_items", %{"filter" => %{"name" => %{"contains" => "hay"}}})

      assert %{"results" => [hay]} = Jason.decode!(json)
      assert Map.keys(hay) |> Enum.sort() == ["id", "name"]
      assert hay["name"] == "Meadow hay"
    end

    test "gives nothing to a person who is no member, and nothing elsewhere", context do
      for {user, tenant} <- outsiders(context), tool <- ["stock_levels", "find_items"] do
        refute call(context, user, tenant, tool, %{}) =~ "hay"
      end
    end
  end
end
