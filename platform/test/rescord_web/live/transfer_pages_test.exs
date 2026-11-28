defmodule RescordWeb.TransferPagesTest do
  @moduledoc """
  Holds the pages of the partners and the transfers (ADR 0042): a question
  to a refuge and its answer, a resident sent with the parts of the form,
  the answer of the refuge that receives it, the copy that its members
  read, the default parts of the settings, and the forms that a member
  does not get. The tests find what a person finds (ADR 0107).

  Each test creates organisations, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Phoenix.LiveViewTest, only: [render_click: 3, render_submit: 3]
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Journal, Transfers}

  setup do
    root = root!()
    wattle = organisation!(root, "Wattle Creek")
    banksia = organisation!(root, "Banksia Rise")
    {_, wattle_admin} = member!(wattle, :administrator, root)
    {_, wattle_member} = member!(wattle, :member, wattle_admin)
    {_, banksia_admin} = member!(banksia, :administrator, root)
    {_, banksia_member} = member!(banksia, :member, banksia_admin)
    lists = lists!(wattle, root)
    biscuit = resident!(lists, actor: wattle_admin, tenant: wattle)

    Journal.write_entry!(
      %{
        resident_id: biscuit.id,
        kind: :vaccination,
        vaccine: "A sample vaccine"
      },
      actor: wattle_admin,
      tenant: wattle
    )

    Journal.write_entry!(
      %{
        resident_id: biscuit.id,
        kind: :diagnosis,
        condition_id: lists.condition.respiratory_infection,
        chronic: true
      },
      actor: wattle_admin,
      tenant: wattle
    )

    {:ok,
     root: root,
     wattle: wattle,
     banksia: banksia,
     wattle_admin: wattle_admin,
     wattle_member: wattle_member,
     banksia_admin: banksia_admin,
     banksia_member: banksia_member,
     biscuit: biscuit}
  end

  defp visit_as(user, path), do: build_conn() |> sign_in(user) |> visit(path)

  defp partnerships, do: main() |> region("Partnerships")
  defp received, do: main() |> region("Received")
  defp sent, do: main() |> region("Sent")
  defp biscuit(part), do: part |> row(~r/^Biscuit\b/)

  defp partners!(context) do
    {:ok, asked} =
      Transfers.ask_partner(context.wattle, context.banksia.short_name,
        actor: context.wattle_admin
      )

    Transfers.accept_partner!(asked, actor: context.banksia_admin)
  end

  test "an administrator asks a refuge, and the other one accepts", context do
    context.wattle_admin
    |> visit_as(~p"/o/#{context.wattle.short_name}/partners")
    |> assert_has(partnerships(), text: "There is no partner refuge yet.")
    |> fill_in("Short name of the refuge", with: context.banksia.short_name)
    |> click(button("Ask the refuge"))
    |> assert_has(partnerships() |> row(~r/^Banksia Rise\b/), state: "info", text: "Asked")
    |> refute_has(partnerships() |> button("Accept Banksia Rise as a partner"))

    context.banksia_admin
    |> visit_as(~p"/o/#{context.banksia.short_name}/partners")
    |> click(partnerships() |> button("Accept Wattle Creek as a partner"))
    |> assert_has(partnerships() |> row(~r/^Wattle Creek\b/), state: "ok", text: "Accepted")
  end

  test "a refuge that does not exist gets an answer in words", context do
    context.wattle_admin
    |> visit_as(~p"/o/#{context.wattle.short_name}/partners")
    |> fill_in("Short name of the refuge", with: "no-such-refuge")
    |> click(button("Ask the refuge"))
    |> assert_has(main() |> alert(), text: "Short name names no other refuge")
  end

  test "a member reads the partners, and has no form and no button", context do
    partners!(context)
    [partnership] = Transfers.partnerships!(actor: context.wattle_member)

    context.wattle_member
    |> visit_as(~p"/o/#{context.wattle.short_name}/partners")
    |> assert_has(partnerships() |> row(~r/^Banksia Rise\b/))
    |> refute_has(main() |> region("Ask a refuge"))
    |> refute_has(partnerships() |> button(~r/./))
    # An event that the page did not offer is refused.
    |> unwrap(&render_click(&1, "end", %{"id" => partnership.id}))
    |> assert_has(main() |> alert())
  end

  test "a resident goes with the parts of the form, and the other refuge accepts it", context do
    partners!(context)

    Accounts.set_organisation_transfer_parts!(context.wattle, [:stay],
      actor: context.wattle_admin
    )

    send = main() |> region("Send a resident")
    stay = "The stay: the arrival, an absence and the departure"

    # The setting ticks the parts at first.
    session = visit_as(context.wattle_admin, ~p"/o/#{context.wattle.short_name}/transfers")
    assert checked?(session, send |> field(stay))
    refute checked?(session, send |> field("The other journal entries"))

    session
    |> within(send, fn form ->
      form
      |> select("Resident", option: "Biscuit")
      |> select("Partner refuge", option: "Banksia Rise")
      |> check("The families, the groups, the parents and the young")
      |> fill_in("Note to the refuge", with: "Shy at first, loves hay.")
      |> click(button("Send the copy"))
    end)
    |> assert_has(biscuit(sent()), state: "info", text: "Waits for an answer")

    [transfer] = Transfers.transfers!(actor: context.wattle_admin)
    assert transfer.parts == [:stay, :relations]

    # The member of the other refuge sees nothing yet.
    context.banksia_member
    |> visit_as(~p"/o/#{context.banksia.short_name}/transfers")
    |> assert_has(received(), text: "No partner refuge has sent you a resident yet.")

    # The refuge that receives it reads the name, and no copy yet.
    context.banksia_admin
    |> visit_as(~p"/o/#{context.banksia.short_name}/transfers")
    |> assert_has(biscuit(received()))
    |> refute_has(biscuit(received()) |> link("Biscuit"))
    |> click(biscuit(received()) |> button("Accept the transfer of Biscuit"))
    |> assert_has(biscuit(received()) |> link("Biscuit"))

    # Each member there reads the copy now.
    conditions = main() |> region("Conditions") |> item(~r/^Respiratory infection\b/)

    context.banksia_member
    |> visit_as(~p"/o/#{context.banksia.short_name}/transfers/#{transfer.id}")
    |> assert_has(main() |> heading(level: 1), text: "Biscuit")
    |> assert_has(main(), text: "A copy from Wattle Creek")
    |> assert_has(main() |> region("Medical history"), text: "Vaccine: A sample vaccine")
    |> assert_has(main() |> region("Medical history"), text: "About Respiratory infection")
    |> assert_has(conditions, text: "Chronic")
    |> assert_has(conditions, text: "Since ")
    |> assert_has(main() |> region("Stay at Wattle Creek"))
    |> assert_has(main() |> region("Families and groups"))
    |> refute_has(main() |> region("Placements at Wattle Creek"))
    |> assert_has(main(), text: "Shy at first, loves hay.")
  end

  test "a copy of another refuge does not open", context do
    partners!(context)

    {:ok, transfer} =
      Transfers.send_transfer(
        %{
          organisation_id: context.wattle.id,
          partner_id: context.banksia.id,
          resident_id: context.biscuit.id
        },
        actor: context.wattle_admin
      )

    third = organisation!(context.root, "Third")
    {_, outsider} = member!(third, :administrator, context.root)

    outsider
    |> visit_as(~p"/o/#{third.short_name}/transfers/#{transfer.id}")
    |> assert_path(~p"/o/#{third.short_name}/transfers")

    # Nor at the refuge that receives it, before it accepts it.
    context.banksia_member
    |> visit_as(~p"/o/#{context.banksia.short_name}/transfers/#{transfer.id}")
    |> assert_path(~p"/o/#{context.banksia.short_name}/transfers")
  end

  test "a member reads the transfers, and has no form", context do
    partners!(context)

    context.wattle_member
    |> visit_as(~p"/o/#{context.wattle.short_name}/transfers")
    |> refute_has(main() |> region("Send a resident"))
    |> unwrap(
      &render_submit(&1, "send", %{
        "transfer" => %{"resident_id" => context.biscuit.id, "partner_id" => context.banksia.id}
      })
    )
    |> assert_has(main() |> alert())

    assert {:ok, []} = Transfers.transfers(actor: context.wattle_admin)
  end

  test "the settings give the parts of a copy, which a member reads", context do
    settings = ~p"/o/#{context.wattle.short_name}/settings"
    parts = main() |> region("Transfers")

    context.wattle_admin
    |> visit_as(settings)
    |> assert_has(parts, text: "No other part: only the facts and the medical history.")
    |> within(parts, fn form ->
      form
      |> check("The other journal entries")
      |> check("The placements")
      |> click(button("Save the parts"))
    end)
    |> assert_has(parts |> item("The other journal entries"))

    assert %{transfer_parts: [:journal, :placements]} =
             Accounts.organisation_by_short_name!(context.wattle.short_name, authorize?: false)

    context.wattle_member
    |> visit_as(settings)
    |> assert_has(parts |> item("The placements"))
    |> refute_has(parts |> button("Save the parts"))
  end

  describe "what the other refuge does (ADR 0096)" do
    test "shows at once on the page of the partners", context do
      session =
        context.banksia_admin
        |> visit_as(~p"/o/#{context.banksia.short_name}/partners")
        |> assert_has(partnerships(), text: "There is no partner refuge yet.")

      {:ok, asked} =
        Transfers.ask_partner(context.wattle, context.banksia.short_name,
          actor: context.wattle_admin
        )

      session
      |> assert_has(partnerships() |> row(~r/^Wattle Creek\b/))
      |> assert_has(partnerships() |> button("Accept Wattle Creek as a partner"))

      # A refuge with no part in it hears nothing, and reads nothing new.
      other = organisation!(context.root, "Ironbark Flat")
      {_, stranger} = member!(other, :administrator, context.root)
      outside = visit_as(stranger, ~p"/o/#{other.short_name}/partners")
      Transfers.accept_partner!(asked, actor: context.banksia_admin)
      assert_has(outside, partnerships(), text: "There is no partner refuge yet.")
    end

    test "shows a transfer that arrives, and its answer at the refuge that sent it", context do
      partners!(context)

      there =
        context.banksia_admin
        |> visit_as(~p"/o/#{context.banksia.short_name}/transfers")
        |> refute_has(biscuit(received()))

      here = visit_as(context.wattle_admin, ~p"/o/#{context.wattle.short_name}/transfers")

      transfer =
        Transfers.send_transfer!(
          %{
            organisation_id: context.wattle.id,
            partner_id: context.banksia.id,
            resident_id: context.biscuit.id
          },
          actor: context.wattle_admin
        )

      assert_has(there, biscuit(received()) |> button("Accept the transfer of Biscuit"))
      assert_has(here, biscuit(sent()), state: "info", text: "Waits for an answer")

      Transfers.accept_transfer!(transfer, actor: context.banksia_admin)
      assert_has(here, biscuit(sent()), state: "ok", text: "Accepted")
    end
  end

  describe "the files of a transfer, which a job copies (ADR 0100)" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} = context do
      Rescord.StorageFixtures.disk_store!(tmp_dir)

      Rescord.Photos.add_photo!(
        %{resident_id: context.biscuit.id, content: Rescord.StorageFixtures.photo()},
        actor: context.wattle_admin,
        tenant: context.wattle
      )

      partners!(context)
      :ok
    end

    defp send_photos!(context) do
      Transfers.send_transfer!(
        %{
          organisation_id: context.wattle.id,
          partner_id: context.banksia.id,
          resident_id: context.biscuit.id,
          parts: [:photos]
        },
        actor: context.wattle_admin
      )
    end

    test "show the count while it sends, and the other refuge after", context do
      here = visit_as(context.wattle_admin, ~p"/o/#{context.wattle.short_name}/transfers")
      there = visit_as(context.banksia_admin, ~p"/o/#{context.banksia.short_name}/transfers")

      send_photos!(context)

      here
      |> assert_has(biscuit(sent()), state: "info", text: "Sending")
      |> assert_has(biscuit(sent()), text: "0 of 2 files")
      |> assert_has(biscuit(sent()) |> details("Withdraw the transfer of Biscuit"))

      refute_has(there, biscuit(received()))

      assert %{success: 1} = Oban.drain_queue(queue: :transfers)

      here
      |> assert_has(biscuit(sent()), state: "info", text: "Waits for an answer")
      |> refute_has(biscuit(sent()), text: "files")

      assert_has(there, biscuit(received()) |> button("Accept the transfer of Biscuit"))
    end

    test "that did not arrive say why, and go again with one click", context do
      Shoddy.Tests.put_app_env(:rescord, :storage, __MODULE__.Refusing)
      send_photos!(context)

      ExUnit.CaptureLog.capture_log(fn ->
        for _try <- 1..10, do: Oban.drain_queue(queue: :transfers, with_scheduled: true)
      end)

      session =
        context.wattle_admin
        |> visit_as(~p"/o/#{context.wattle.short_name}/transfers")
        |> assert_has(biscuit(sent()), state: "alert", text: "Not sent")
        |> assert_has(biscuit(sent()), text: "could not reach the files")

      # A member reads it, and has no button.
      context.wattle_member
      |> visit_as(~p"/o/#{context.wattle.short_name}/transfers")
      |> assert_has(biscuit(sent()), state: "alert", text: "Not sent")
      |> refute_has(biscuit(sent()) |> button(~r/./))
      |> refute_has(biscuit(sent()) |> details(~r/./))

      Shoddy.Tests.put_app_env(:rescord, :storage, Rescord.Storage.Disk)

      session
      |> click(biscuit(sent()) |> button("Send the transfer of Biscuit again"))
      |> assert_has(biscuit(sent()), state: "info", text: "Sending")
      |> refute_has(biscuit(sent()) |> button("Send the transfer of Biscuit again"))
    end
  end

  # A store that refuses each file of a transfer.
  defmodule Refusing do
    @moduledoc false
    @behaviour Rescord.Storage

    alias Rescord.Storage.Disk

    @impl true
    def put(key, bytes, type) do
      if key =~ "/transfers/", do: {:error, :refused}, else: Disk.put(key, bytes, type)
    end

    @impl true
    defdelegate get(key), to: Disk
    @impl true
    defdelegate delete(key), to: Disk
    @impl true
    defdelegate list, to: Disk
    @impl true
    defdelegate files, to: Disk
  end
end
