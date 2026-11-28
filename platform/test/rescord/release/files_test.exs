defmodule Rescord.Release.FilesTest do
  @moduledoc """
  Holds the comparison of the store with the database (ADR 0091), with the
  records of real actions: each fault that leaves a file with no record,
  each record that names a file, the removed ones and the old versions
  too, and a record whose file is gone. `Rescord.Storage.CompareTest`
  holds the comparison itself and the words of the report.

  It also holds that no resource with the key of a file is outside the
  domains that `Rescord.Release.Files` asks.

  Each test creates organisations, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.StorageFixtures

  alias Rescord.{Expenses, Journal, Photos, Repo, Storage, Transfers}
  alias Rescord.Release.Files
  alias Rescord.Storage.Disk

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    disk_store!(tmp_dir)
    root = root!()
    wattle = organisation!(root, "Wattle Creek")
    banksia = organisation!(root, "Banksia Rise")
    {_, wattle_admin} = member!(wattle, :administrator, root)
    {_, banksia_admin} = member!(banksia, :administrator, root)
    lists = lists!(wattle, root)
    options = [actor: wattle_admin, tenant: wattle]
    biscuit = resident!(lists, options)

    {:ok,
     wattle: wattle,
     banksia: banksia,
     wattle_admin: wattle_admin,
     banksia_admin: banksia_admin,
     lists: lists,
     options: options,
     biscuit: biscuit}
  end

  defp compare! do
    assert {:ok, report} = Files.compare()
    report
  end

  defp keys(files), do: Enum.map(files, &elem(&1, 0))

  defp add_photo!(context, content \\ photo()),
    do: Photos.add_photo!(%{resident_id: context.biscuit.id, content: content}, context.options)

  defp entry_with_files(context, files) do
    Journal.write_entry_with_files(
      %{resident_id: context.biscuit.id, kind: :general, note: "In the garden."},
      files,
      context.options
    )
  end

  defp attachments!(context, entry) do
    {:ok, by_entry} = Journal.attachments_of([entry.id], context.options)
    Map.fetch!(by_entry, entry.id)
  end

  defp partners!(context) do
    {:ok, asked} =
      Transfers.ask_partner(context.wattle, context.banksia.short_name,
        actor: context.wattle_admin
      )

    {:ok, _accepted} = Transfers.accept_partner(asked, actor: context.banksia_admin)
    :ok
  end

  defp send_transfer(context) do
    Transfers.send_transfer(
      %{
        organisation_id: context.wattle.id,
        partner_id: context.banksia.id,
        resident_id: context.biscuit.id,
        parts: [:photos]
      },
      actor: context.wattle_admin
    )
  end

  # A store that takes each file but those whose key the test refuses.
  defmodule Refusing do
    @moduledoc false
    @behaviour Rescord.Storage

    @impl true
    def put(key, bytes, type) do
      if Process.get(:refuse, fn _key -> false end).(key),
        do: {:error, :refused},
        else: Disk.put(key, bytes, type)
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

  defp refuse!(refuse) do
    Process.put(:refuse, refuse)
    Shoddy.Tests.put_app_env(:rescord, :storage, Refusing)
  end

  describe "a file that no record names" do
    test "stays when the thumbnail of a photo fails after the photo went in", context do
      refuse!(&(&1 =~ "/thumbnails/"))

      assert {:error, _error} =
               Photos.add_photo(
                 %{resident_id: context.biscuit.id, content: photo()},
                 context.options
               )

      report = compare!()
      assert [{key, size}] = report.leftover
      assert key =~ ~r"^#{context.wattle.id}/photos/"
      assert {:ok, bytes} = Storage.get(key)
      assert size == byte_size(bytes)
      assert report.named.count == 0
      assert report.missing == []
    end

    test "stays when a later file of the same journal entry is refused", context do
      assert {:error, _error} =
               entry_with_files(context, [{"garden.jpg", jpeg()}, {"notes.txt", "no file type"}])

      report = compare!()
      organisation = context.wattle.id

      assert [
               <<^organisation::binary-size(36), "/attachments/", _id::binary>>,
               <<^organisation::binary-size(36), "/thumbnails/", _same::binary>>
             ] = keys(report.leftover)

      assert report.missing == []
    end

    test "stays when a file in the middle of a transfer fails", context do
      partners!(context)
      add_photo!(context)
      add_photo!(context, photo(width: 80))
      Process.put(:puts, 0)

      # The store takes the first file of the transfer, and no second one.
      refuse!(fn key ->
        key =~ "/transfers/" and Process.put(:puts, Process.get(:puts) + 1) >= 1
      end)

      assert {:error, _error} = send_transfer(context)

      report = compare!()
      assert [key] = keys(report.leftover)
      assert key =~ ~r"^#{context.banksia.id}/transfers/"
      assert report.named.count == 4
      assert report.missing == []
    end

    test "stays when the transaction of an upload does not commit", context do
      # `Ash.transact/3`, so that Ash knows of the transaction and drops the
      # notification of the photo that does not commit (ADR 0096).
      assert {:error, %Ash.Error.Unknown.UnknownError{error: "unknown error: :stopped"}} =
               Ash.transact(Rescord.Photos.Photo, fn ->
                 add_photo!(context)
                 Repo.rollback(:stopped)
               end)

      report = compare!()
      assert [photo, thumbnail] = keys(report.leftover)
      assert photo =~ "/photos/"
      assert thumbnail =~ "/thumbnails/"
    end

    test "is counted apart when its first segment is no organisation, or it is no key",
         %{tmp_dir: tmp_dir} = context do
      photo = add_photo!(context)
      :ok = Storage.put("check/probe/0a1b2c3d", "Rescord checks its store.\n", "text/plain")
      File.write!(Path.join(tmp_dir, "notes.txt"), "of the operator")

      report = compare!()
      assert report.unknown == [{"check/probe/0a1b2c3d", 26}]
      assert report.other == [{"notes.txt", 15}]
      assert report.leftover == []
      assert report.named.count == 2
      assert report.store.count == 4
      assert report.organisations == 2

      assert report.named.bytes ==
               photo.size + byte_size(elem(Storage.get(photo.thumbnail_key), 1))
    end
  end

  describe "a file that a record names" do
    test "is named by a removed attachment, a removed receipt and each version of a photo",
         context do
      {:ok, entry} = entry_with_files(context, [{"garden.jpg", jpeg()}, {"report.pdf", pdf()}])
      [photo_file, _report] = attachments!(context, entry)
      :ok = Journal.remove_attachment(photo_file, context.options)

      expense =
        Expenses.submit_expense!(
          %{
            paid_by: :member,
            amount: "186.00",
            incurred_on: Rescord.Accounts.today(context.wattle),
            payee: "Northside Vet Clinic",
            description: "Vet consult",
            category_id: context.lists.expense_category.veterinary
          },
          context.options
        )

      receipt =
        Expenses.attach_receipt!(
          %{expense_id: expense.id, name: "receipt.jpg", content: jpeg()},
          context.options
        )

      :ok = Expenses.remove_receipt(receipt, context.options)

      photo = add_photo!(context)
      {:ok, photo} = Photos.describe_photo(photo, %{caption: "On the sofa"}, context.options)
      :ok = Photos.remove_photo(photo, context.options)

      report = compare!()
      # A photo and a thumbnail for each of the three, and the PDF.
      assert report.named.count == 7
      assert report.store.count == 7
      assert report.leftover == []
      assert report.missing == []
    end

    test "is named one time when a photo uses the file of a journal entry", context do
      {:ok, entry} = entry_with_files(context, [{"garden.jpg", jpeg()}])
      [attachment] = attachments!(context, entry)
      {:ok, adopted} = Photos.adopt(attachment.id, context.options)
      assert adopted.key == attachment.key

      report = compare!()
      assert report.named.count == 2
      assert report.leftover == []

      # Both records name the file when it is gone.
      :ok = Storage.delete(attachment.key)

      assert [{key, organisation_id, records, :not_found}] = compare!().missing
      assert key == attachment.key
      assert organisation_id == context.wattle.id
      assert records == [{"journal attachment", attachment.id}, {"photo", adopted.id}]
    end

    test "is named by a transfer in each state, for the refuge that received it", context do
      partners!(context)
      add_photo!(context)

      {:ok, sent} = send_transfer(context)
      {:ok, accepted} = send_transfer(context)
      {:ok, _accepted} = Transfers.accept_transfer(accepted, actor: context.banksia_admin)
      {:ok, declined} = send_transfer(context)
      {:ok, _declined} = Transfers.decline_transfer(declined, actor: context.banksia_admin)
      {:ok, withdrawn} = send_transfer(context)
      {:ok, _withdrawn} = Transfers.withdraw_transfer(withdrawn, actor: context.wattle_admin)

      report = compare!()
      # The photo and its thumbnail, and a copy of both for each transfer.
      assert report.named.count == 2 + 4 * 2
      assert report.leftover == []
      assert report.missing == []

      keys = Transfers.file_keys(context.banksia.id)
      assert length(keys) == 8

      assert Enum.all?(keys, fn {key, kind, _id} ->
               kind == "transfer" and key =~ "/transfers/"
             end)

      assert keys |> Enum.map(&elem(&1, 2)) |> Enum.uniq() |> Enum.sort() ==
               Enum.sort([sent.id, accepted.id, declined.id, withdrawn.id])

      # The refuge that sent them has no file of a transfer.
      assert Transfers.file_keys(context.wattle.id) == []
    end

    test "is missing when the store lost it, with the record that names it", context do
      photo = add_photo!(context)
      kept = add_photo!(context, photo(width: 80))
      :ok = Storage.delete(photo.thumbnail_key)

      report = compare!()

      assert report.missing == [
               {photo.thumbnail_key, context.wattle.id, [{"photo", photo.id}], :not_found}
             ]

      assert report.named.count == 3
      assert kept.key in keys(Disk.files() |> elem(1))
    end
  end

  describe "what stops the comparison" do
    test "is a store that cannot list its files", %{tmp_dir: tmp_dir} do
      missing = Path.join(tmp_dir, "none")
      Shoddy.Tests.put_app_env(:rescord, Disk, root: missing)
      assert Files.compare() == {:error, {:list, {:enoent, missing}}}
    end
  end

  describe "the domains that keep files" do
    # A record of a file holds its key in the text attribute `key`.
    defp file_resources do
      for domain <- Application.fetch_env!(:rescord, :ash_domains),
          resource <- Ash.Domain.Info.resources(domain),
          match?(%{type: Ash.Type.String}, Ash.Resource.Info.attribute(resource, :key)),
          do: {domain, resource}
    end

    test "are the domains of each resource with the key of a file" do
      resources = file_resources()

      # The versions of a temporal resource are rows of its own table.
      tables =
        for {_domain, resource} <- resources, do: AshPostgres.DataLayer.Info.table(resource)

      assert tables |> Enum.uniq() |> Enum.sort() ==
               ["expense_receipts", "journal_attachments", "photos"]

      for {domain, resource} <- resources do
        assert domain in Files.domains(),
               "#{inspect(resource)} has the key of a file, and Rescord.Release.Files " <>
                 "does not ask #{inspect(domain)}: bin/check-files would call each of its " <>
                 "files a leftover"
      end
    end

    test "each read the table of each such resource", context do
      test = self()
      handler = {__MODULE__, make_ref()}

      :telemetry.attach(
        handler,
        [:rescord, :repo, :query],
        fn _event, _measurements, metadata, _config -> send(test, {:read, metadata.source}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      for {domain, resource} <- file_resources() do
        table = AshPostgres.DataLayer.Info.table(resource)
        assert is_list(domain.file_keys(context.wattle.id))

        assert_received {:read, ^table},
                        "#{inspect(domain)}.file_keys/1 does not read the table #{table} of " <>
                          "#{inspect(resource)}: bin/check-files would call each of its files " <>
                          "a leftover"
      end
    end

    test "each give the keys of one organisation, and not of another", context do
      photo = add_photo!(context)

      assert Enum.sort(Photos.file_keys(context.wattle.id)) ==
               Enum.sort([
                 {photo.key, "photo", photo.id},
                 {photo.thumbnail_key, "photo", photo.id}
               ])

      for domain <- Files.domains(), do: assert(domain.file_keys(context.banksia.id) == [])
    end
  end
end
