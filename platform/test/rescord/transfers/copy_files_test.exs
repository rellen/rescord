defmodule Rescord.Transfers.CopyFilesTest do
  @moduledoc """
  Holds the job that copies the files of a transfer (ADR 0100): the send
  returns before a file is copied, the refuge that receives it sees
  nothing until the job delivered it, a fault in the middle and the try
  that starts at the count, a file that is not in the store, the last of
  the 10 tries, a withdraw while the job copies, a transfer sent again,
  who runs what, and the versions that the job leaves.

  Each test creates organisations, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import ExUnit.CaptureLog
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.StorageFixtures

  require Ash.Query

  alias Rescord.{Photos, Storage, Transfers}
  alias Rescord.Storage.Disk
  alias Rescord.Transfers.Transfer

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    disk_store!(tmp_dir)
    root = root!()
    wattle = organisation!(root, "Wattle Creek")
    banksia = organisation!(root, "Banksia Rise")
    {_, wattle_admin} = member!(wattle, :administrator, root)
    {_, wattle_member} = member!(wattle, :member, wattle_admin)
    {_, banksia_admin} = member!(banksia, :administrator, root)
    lists = lists!(wattle, root)
    options = [actor: wattle_admin, tenant: wattle]
    biscuit = resident!(lists, options)
    Photos.add_photo!(%{resident_id: biscuit.id, content: photo()}, options)

    {:ok, asked} =
      Transfers.ask_partner(wattle, banksia.short_name, actor: wattle_admin)

    {:ok, _accepted} = Transfers.accept_partner(asked, actor: banksia_admin)

    {:ok,
     wattle: wattle,
     banksia: banksia,
     wattle_admin: wattle_admin,
     wattle_member: wattle_member,
     banksia_admin: banksia_admin,
     biscuit: biscuit}
  end

  # A store that runs the hook of the test before each put of a file of a
  # transfer: `:ok` puts it, and an error refuses it.
  defmodule Hooked do
    @moduledoc false
    @behaviour Rescord.Storage

    @impl true
    def put(key, bytes, type) do
      hook = Process.get(:hook, fn _key -> :ok end)

      with :ok <- if(key =~ "/transfers/", do: hook.(key), else: :ok) do
        Process.put(:puts, Process.get(:puts, []) ++ [key])
        Disk.put(key, bytes, type)
      end
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

  defp hook!(hook) do
    Process.put(:hook, hook)
    Shoddy.Tests.put_app_env(:rescord, :storage, Hooked)
  end

  defp puts, do: Process.get(:puts, [])

  defp send!(context, parts \\ [:photos]) do
    assert {:ok, transfer} =
             Transfers.send_transfer(
               %{
                 organisation_id: context.wattle.id,
                 partner_id: context.banksia.id,
                 resident_id: context.biscuit.id,
                 parts: parts
               },
               actor: context.wattle_admin
             )

    transfer
  end

  defp drain(opts \\ []), do: Oban.drain_queue([queue: :transfers] ++ opts)

  defp reload(transfer),
    do: Ash.get!(Transfer, transfer.id, authorize?: false)

  defp transfer_files(context) do
    {:ok, files} = Storage.files()

    for {key, _size} <- files,
        String.starts_with?(key, "#{context.banksia.id}/transfers/"),
        do: key
  end

  defp versions(transfer) do
    Transfer.Version
    |> Ash.Query.filter(version_source_id == ^transfer.id)
    |> Ash.Query.sort(version_inserted_at: :asc)
    |> Ash.read!(authorize?: false)
  end

  describe "the send" do
    test "returns before a file is copied, and the job delivers the transfer", context do
      transfer = send!(context)

      # The photo and its thumbnail.
      assert transfer.state == :sending
      assert transfer.files_total == 2
      assert transfer.files_copied == 0
      assert transfer_files(context) == []

      # The refuge that receives it sees nothing while it is sending.
      assert {:ok, nil} = Transfers.transfer(transfer.id, actor: context.banksia_admin)
      assert {:ok, []} = Transfers.transfers(actor: context.banksia_admin)

      assert %{success: 1, failure: 0} = drain()

      transfer = reload(transfer)
      assert transfer.state == :sent
      assert transfer.files_copied == 2
      assert transfer.sources == nil
      assert length(transfer_files(context)) == 2

      assert {:ok, %Transfer{state: :sent}} =
               Transfers.transfer(transfer.id, actor: context.banksia_admin)
    end

    test "of a transfer with no file is sent at once, with no job", context do
      transfer = send!(context, [])

      assert transfer.state == :sent
      assert transfer.files_total == 0
      assert %{success: 0, failure: 0} = drain()
    end
  end

  describe "a fault of the store" do
    test "stops the job, and the next try starts at the count", context do
      # The store refuses the second file one time.
      hook!(fn _key ->
        if length(puts()) == 1 and not Process.get(:refused?, false) do
          Process.put(:refused?, true)
          {:error, :refused}
        else
          :ok
        end
      end)

      transfer = send!(context)

      log = capture_log(fn -> assert %{failure: 1} = drain() end)
      assert log =~ "The copy of the files of a transfer failed"

      transfer = reload(transfer)
      assert transfer.state == :sending
      assert transfer.files_copied == 1

      assert %{success: 1} = drain(with_scheduled: true)
      assert reload(transfer).state == :sent

      # The first file went in one time, and the second one after the fault.
      assert [first, second] = puts()
      assert first != second
    end

    test "on each of the 10 tries makes the transfer failed", context do
      hook!(fn _key -> {:error, :refused} end)
      transfer = send!(context)

      capture_log(fn ->
        for _try <- 1..9, do: assert(%{failure: 1} = drain(with_scheduled: true))
        assert %{success: 1} = drain(with_scheduled: true)
      end)

      transfer = reload(transfer)
      assert transfer.state == :failed
      assert transfer.failure == :store_refused
      assert transfer.files_copied == 0
      assert %{success: 0, failure: 0} = drain(with_scheduled: true)

      # The refuge that receives it does not see it.
      assert {:ok, nil} = Transfers.transfer(transfer.id, actor: context.banksia_admin)
    end
  end

  describe "a file that is not in the store of the refuge that sent it" do
    test "makes the transfer failed at once, and it goes again when the file is back",
         context do
      transfer = send!(context)
      [source | _] = transfer.sources
      {:ok, bytes} = Storage.get(source["key"])
      :ok = Storage.delete(source["key"])

      log = capture_log(fn -> assert %{success: 1} = drain() end)
      assert log =~ "is not in the store"

      failed = reload(transfer)
      assert failed.state == :failed
      assert failed.failure == :file_missing

      # A member has no power to send it again, and the other refuge either.
      assert {:error, %Ash.Error.Forbidden{}} =
               Transfers.send_transfer_again(failed, actor: context.wattle_member)

      assert {:error, %Ash.Error.Forbidden{}} =
               Transfers.send_transfer_again(failed, actor: context.banksia_admin)

      :ok = Storage.put(source["key"], bytes, "image/jpeg")

      assert {:ok, again} = Transfers.send_transfer_again(failed, actor: context.wattle_admin)
      assert again.state == :sending
      assert again.failure == nil

      # The transfer that is sending is sent again no more.
      assert {:error, _error} = Transfers.send_transfer_again(again, actor: context.wattle_admin)

      assert %{success: 1} = drain()
      assert reload(transfer).state == :sent
    end
  end

  describe "a withdraw while the job copies" do
    test "stops the job", context do
      transfer = send!(context)

      hook!(fn _key ->
        {:ok, _withdrawn} =
          Transfers.withdraw_transfer(reload(transfer), actor: context.wattle_admin)

        :ok
      end)

      assert %{success: 1} = drain()

      withdrawn = reload(transfer)
      assert withdrawn.state == :withdrawn
      assert length(puts()) == 1

      # The count names the file that the job put, so the file check finds
      # no leftover (ADR 0091).
      assert withdrawn.files_copied == 1
      assert [{key, "transfer", _id}] = Transfers.file_keys(context.banksia.id)
      assert puts() == [key]
    end

    test "of a transfer that failed is taken too", context do
      hook!(fn _key -> {:error, :refused} end)
      transfer = send!(context)
      capture_log(fn -> for _try <- 1..10, do: drain(with_scheduled: true) end)
      assert reload(transfer).state == :failed

      assert {:ok, %{state: :withdrawn}} =
               Transfers.withdraw_transfer(reload(transfer), actor: context.wattle_admin)
    end
  end

  describe "the steps of the job" do
    test "are run by no person", context do
      transfer = send!(context)

      for {action, input} <- [
            progress: %{files_copied: 1},
            deliver: %{},
            fail: %{failure: :store_refused}
          ],
          actor <- [context.wattle_admin, context.banksia_admin] do
        assert {:error, %Ash.Error.Forbidden{}} =
                 transfer
                 |> Ash.Changeset.for_update(action, input, actor: actor)
                 |> Ash.update()
      end

      assert {:error, %Ash.Error.Forbidden{}} =
               Transfer
               |> Ash.ActionInput.for_action(
                 :copy_files,
                 %{
                   signal: %Rescord.Transfers.Signals.TransferStarted{
                     signal_id: Ash.UUID.generate(),
                     transfer_id: transfer.id
                   }
                 },
                 actor: context.wattle_admin
               )
               |> Ash.run_action()

      assert reload(transfer).state == :sending
    end

    test "write a count that never goes back, and none after the end", context do
      transfer = send!(context)

      write = fn record, count ->
        record
        |> Ash.Changeset.for_update(:progress, %{files_copied: count}, authorize?: false)
        |> Ash.update()
      end

      assert {:ok, %{files_copied: 2}} = write.(transfer, 2)
      assert {:ok, %{files_copied: 2}} = write.(transfer, 1)

      assert %{success: 1} = drain()
      sent = reload(transfer)
      assert sent.state == :sent

      # An old job of the same transfer writes nothing after the end.
      assert {:error, %Ash.Error.Invalid{}} = write.(sent, 2)
    end

    test "leave a version for the send and one for the end, and none for the count",
         context do
      transfer = send!(context)
      assert %{success: 1} = drain()

      assert [:send, :deliver] = transfer |> versions() |> Enum.map(& &1.version_action_name)
    end
  end
end
