defmodule RescordWeb.Features.InventoryTest do
  @moduledoc """
  Records a use of stock through a real browser.

  `RescordWeb.InventoryPagesTest` holds each rule of the pages. This test
  holds what only a browser shows: each form of the page of an item is in a
  part of the page that is closed at first, and a refusal is in that part,
  which stays open with what the member typed.

  The test creates an organisation, so it does not run beside others (see
  `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.FeatureCase, async: false

  import Rescord.ResidentsFixtures

  alias Rescord.{Inventory, Locations}

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_member, user} = member!(organisation, :member, root)
    lists = lists!(organisation, root)
    options = [actor: root, tenant: organisation]

    shed = Locations.add_location!(%{name: "Feed shed"}, options)
    hay = Inventory.add_item!(%{name: "Meadow hay", unit_id: lists.unit.bag}, options)

    Inventory.receive_lot!(
      %{item_id: hay.id, code: "B-1", quantity: 10, location_id: shed.id},
      options
    )

    # The email of the invitation is not what the test looks at.
    flush_emails()

    {:ok,
     address: to_string(user.email), path: "/o/#{organisation.short_name}/inventory/#{hay.id}"}
  end

  test "a member records a use, and a refusal is in the form, which stays open",
       %{conn: session, address: address, path: path} do
    session
    |> sign_in_with_link(address)
    |> visit(path)
    |> assert_connected()
    |> assert_has("#lots li", text: "Feed shed: 10 bag")
    |> click("summary", "Stock was used")
    |> fill_in("How much was used, in bag", with: "0")
    |> click_button("Record the use")
    |> assert_has("#use p[role=alert]", text: "Quantity must be more than zero")
    |> evaluate("document.getElementById('use').open", fn open -> assert open end)
    |> evaluate("document.getElementById('use_quantity').value", fn value ->
      assert value == "0"
    end)
    |> fill_in("How much was used, in bag", with: "6.5")
    |> click_button("Record the use")
    |> assert_has("#history td", text: "Used")
    |> assert_has("#lots li", text: "Feed shed: 3.5 bag")
  end
end
