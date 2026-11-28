defmodule RescordWeb.TransferPagesTest do
  @moduledoc """
  Holds the pages of the partners and the transfers (ADR 0042): a question
  to a refuge and its answer, a resident sent with the parts of the form,
  the answer of the refuge that receives it, the copy that its members
  read, the default parts of the settings, and the forms that a member
  does not get.

  Each test creates organisations, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
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

  defp open(user, path) do
    conn = build_conn() |> sign_in(user)
    {:ok, view, _html} = live(conn, path)
    {conn, view, render_async(view)}
  end

  defp submit(view, conn, selector, fields) do
    {:ok, view, _html} =
      view |> form(selector, fields) |> render_submit() |> follow_redirect(conn)

    {view, render_async(view)}
  end

  defp partners!(context) do
    {:ok, asked} =
      Transfers.ask_partner(context.wattle, context.banksia.short_name,
        actor: context.wattle_admin
      )

    Transfers.accept_partner!(asked, actor: context.banksia_admin)
  end

  test "an administrator asks a refuge, and the other one accepts", context do
    {conn, view, _html} = open(context.wattle_admin, ~p"/o/#{context.wattle.short_name}/partners")
    assert has_element?(view, "p", "There is no partner refuge yet.")

    {view, _html} =
      submit(view, conn, "#ask", partner: %{short_name: context.banksia.short_name})

    assert has_element?(view, "tbody td", "Banksia Rise")
    assert has_element?(view, "[data-state=info]", "Asked")
    refute has_element?(view, "button", "Accept")

    {conn, view, _html} =
      open(context.banksia_admin, ~p"/o/#{context.banksia.short_name}/partners")

    [partnership] = Transfers.partnerships!(actor: context.banksia_admin)

    {:ok, view, _html} =
      view |> render_click("accept", %{"id" => partnership.id}) |> follow_redirect(conn)

    assert has_element?(view, "tbody td", "Wattle Creek")
    assert has_element?(view, "[data-state=ok]", "Accepted")
  end

  test "a refuge that does not exist gets an answer in words", context do
    {_conn, view, _html} =
      open(context.wattle_admin, ~p"/o/#{context.wattle.short_name}/partners")

    view |> form("#ask", partner: %{short_name: "no-such-refuge"}) |> render_submit()
    assert has_element?(view, "main p[role=alert]", "Short name names no other refuge")
  end

  test "a member reads the partners, and has no form and no button", context do
    partners!(context)

    {_conn, view, _html} =
      open(context.wattle_member, ~p"/o/#{context.wattle.short_name}/partners")

    assert has_element?(view, "tbody td", "Banksia Rise")
    refute has_element?(view, "#ask")
    refute has_element?(view, "tbody button")

    # An event that the page did not offer is refused.
    [partnership] = Transfers.partnerships!(actor: context.wattle_member)
    render_click(view, "end", %{"id" => partnership.id})
    assert has_element?(view, "main p[role=alert]")
  end

  test "a resident goes with the parts of the form, and the other refuge accepts it", context do
    partners!(context)

    Accounts.set_organisation_transfer_parts!(context.wattle, [:stay],
      actor: context.wattle_admin
    )

    {conn, view, _html} =
      open(context.wattle_admin, ~p"/o/#{context.wattle.short_name}/transfers")

    # The setting ticks the parts at first.
    assert has_element?(view, "#send input[value=stay][checked]")
    refute has_element?(view, "#send input[value=journal][checked]")

    {view, _html} =
      submit(view, conn, "#send",
        transfer: %{
          resident_id: context.biscuit.id,
          partner_id: context.banksia.id,
          parts: ["stay", "relations"],
          note: "Shy at first, loves hay."
        }
      )

    assert has_element?(view, "#sent tbody td", "Biscuit")
    assert has_element?(view, "#sent [data-state=info]", "Waits for an answer")

    [transfer] = Transfers.transfers!(actor: context.wattle_admin)
    assert transfer.parts == [:stay, :relations]

    # The member of the other refuge sees nothing yet.
    {_conn, view, _html} =
      open(context.banksia_member, ~p"/o/#{context.banksia.short_name}/transfers")

    assert has_element?(view, "#received p", "No partner refuge has sent you a resident yet.")

    {conn, view, _html} =
      open(context.banksia_admin, ~p"/o/#{context.banksia.short_name}/transfers")

    assert has_element?(view, "#received tbody td span", "Biscuit")

    {:ok, _view, _html} =
      view |> render_click("accept", %{"id" => transfer.id}) |> follow_redirect(conn)

    # Each member there reads the copy now.
    {_conn, view, _html} =
      open(context.banksia_member, ~p"/o/#{context.banksia.short_name}/transfers/#{transfer.id}")

    assert has_element?(view, "h1", "Biscuit")
    assert has_element?(view, "p", "A copy from Wattle Creek")
    assert has_element?(view, "#copy-medical ~ article p", "Vaccine: A sample vaccine")
    assert has_element?(view, "#copy-conditions ~ ul li strong", "Respiratory infection")
    assert has_element?(view, "#copy-conditions ~ ul li", "Chronic")
    assert has_element?(view, "#copy-conditions ~ ul li small", "Since ")

    assert has_element?(
             view,
             "#copy-medical ~ article p[data-about]",
             "About Respiratory infection"
           )

    assert has_element?(view, "h2", "Stay at Wattle Creek")
    assert has_element?(view, "h2", "Families and groups")
    refute has_element?(view, "h2", "Placements at Wattle Creek")
    assert has_element?(view, "p", "Shy at first, loves hay.")
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
    conn = build_conn() |> sign_in(outsider)

    assert {:error, {:live_redirect, %{to: "/o/" <> _}}} =
             live(conn, ~p"/o/#{third.short_name}/transfers/#{transfer.id}")

    # Nor at the refuge that receives it, before it accepts it.
    conn = build_conn() |> sign_in(context.banksia_member)

    assert {:error, {:live_redirect, _}} =
             live(conn, ~p"/o/#{context.banksia.short_name}/transfers/#{transfer.id}")
  end

  test "a member reads the transfers, and has no form", context do
    partners!(context)

    {_conn, view, _html} =
      open(context.wattle_member, ~p"/o/#{context.wattle.short_name}/transfers")

    refute has_element?(view, "#send")

    render_submit(view, "send", %{
      "transfer" => %{"resident_id" => context.biscuit.id, "partner_id" => context.banksia.id}
    })

    assert has_element?(view, "main p[role=alert]")
    assert {:ok, []} = Transfers.transfers(actor: context.wattle_admin)
  end

  test "the settings give the parts of a copy, which a member reads", context do
    {conn, view, _html} =
      open(context.wattle_admin, ~p"/o/#{context.wattle.short_name}/settings")

    assert has_element?(view, "p", "No other part: only the facts and the medical history.")

    {_view, html} = submit(view, conn, "#parts", parts: %{keys: ["journal", "placements"]})
    assert html =~ "The other journal entries"

    assert %{transfer_parts: [:journal, :placements]} =
             Accounts.organisation_by_short_name!(context.wattle.short_name, authorize?: false)

    {_conn, view, _html} =
      open(context.wattle_member, ~p"/o/#{context.wattle.short_name}/settings")

    assert has_element?(view, "li", "The placements")
    refute has_element?(view, "#parts")
  end

  describe "what the other refuge does (ADR 0096)" do
    test "shows at once on the page of the partners", context do
      {_conn, view, _html} =
        open(context.banksia_admin, ~p"/o/#{context.banksia.short_name}/partners")

      assert has_element?(view, "p", "There is no partner refuge yet.")

      {:ok, asked} =
        Transfers.ask_partner(context.wattle, context.banksia.short_name,
          actor: context.wattle_admin
        )

      assert has_element?(view, "tbody td", "Wattle Creek")
      assert has_element?(view, "button", "Accept")

      # A refuge with no part in it hears nothing, and reads nothing new.
      other = organisation!(context.root, "Ironbark Flat")
      {_, stranger} = member!(other, :administrator, context.root)
      {_conn, outside, _html} = open(stranger, ~p"/o/#{other.short_name}/partners")
      Transfers.accept_partner!(asked, actor: context.banksia_admin)
      assert has_element?(outside, "p", "There is no partner refuge yet.")
    end

    test "shows a transfer that arrives, and its answer at the refuge that sent it", context do
      partners!(context)

      {_conn, there, _html} =
        open(context.banksia_admin, ~p"/o/#{context.banksia.short_name}/transfers")

      {_conn, here, _html} =
        open(context.wattle_admin, ~p"/o/#{context.wattle.short_name}/transfers")

      refute render(there) =~ "Biscuit"

      transfer =
        Transfers.send_transfer!(
          %{
            organisation_id: context.wattle.id,
            partner_id: context.banksia.id,
            resident_id: context.biscuit.id
          },
          actor: context.wattle_admin
        )

      assert render(there) =~ "Biscuit"
      assert has_element?(there, "button", "Accept")
      assert has_element?(here, "[data-state=info]", "Waits for an answer")

      Transfers.accept_transfer!(transfer, actor: context.banksia_admin)
      assert has_element?(here, "[data-state=ok]", "Accepted")
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
      {_conn, here, _html} =
        open(context.wattle_admin, ~p"/o/#{context.wattle.short_name}/transfers")

      {_conn, there, _html} =
        open(context.banksia_admin, ~p"/o/#{context.banksia.short_name}/transfers")

      send_photos!(context)

      assert has_element?(here, "#sent [data-state=info]", "Sending")
      assert has_element?(here, "#sent td small", "0 of 2 files")
      assert has_element?(here, "#sent button", "Withdraw")
      refute render(there) =~ "Biscuit"

      assert %{success: 1} = Oban.drain_queue(queue: :transfers)

      assert has_element?(here, "#sent [data-state=info]", "Waits for an answer")
      refute has_element?(here, "#sent td small")
      assert render(there) =~ "Biscuit"
      assert has_element?(there, "button", "Accept")
    end

    test "that did not arrive say why, and go again with one click", context do
      Shoddy.Tests.put_app_env(:rescord, :storage, __MODULE__.Refusing)
      transfer = send_photos!(context)

      ExUnit.CaptureLog.capture_log(fn ->
        for _try <- 1..10, do: Oban.drain_queue(queue: :transfers, with_scheduled: true)
      end)

      {conn, view, _html} =
        open(context.wattle_admin, ~p"/o/#{context.wattle.short_name}/transfers")

      assert has_element?(view, "#sent [data-state=alert]", "Not sent")
      assert has_element?(view, "#sent td small", "could not reach the files")

      # A member reads it, and has no button.
      {_conn, member_view, _html} =
        open(context.wattle_member, ~p"/o/#{context.wattle.short_name}/transfers")

      assert has_element?(member_view, "#sent [data-state=alert]", "Not sent")
      refute has_element?(member_view, "#sent button")

      Shoddy.Tests.put_app_env(:rescord, :storage, Rescord.Storage.Disk)

      {:ok, view, _html} =
        view |> render_click("send_again", %{"id" => transfer.id}) |> follow_redirect(conn)

      assert has_element?(view, "#sent [data-state=info]", "Sending")
      refute has_element?(view, "#sent button", "Send again")
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
