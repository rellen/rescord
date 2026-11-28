defmodule Rescord.Transfers.CheckFilesTest do
  @moduledoc """
  Holds the check of the files of an import (issue 37, ADR 0113): the job
  writes each photo of the copy again with no metadata and nothing after
  the image, with its new size in the copy; the files stay closed until
  it ends; a photo that libvips cannot read fails the check; with the
  virus scan on, a harmful PDF fails it, and a clamd that does not answer
  makes the job try again, then fail, until the receiver checks again.

  The job runs with `Oban.drain_queue/1`, in the process of the test. Each
  test creates organisations, so the tests do not run beside others (see
  `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import ExUnit.CaptureLog
  import Rescord.AccountsFixtures
  import Rescord.StorageFixtures

  alias Rescord.{FakeClamd, Images, Transfers}
  alias Rescord.Storage.Scan
  alias Rescord.Transfers.{Archive, Keys}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    disk_store!(tmp_dir)
    root = root!()
    wattle = organisation!(root, "Wattle Creek")
    banksia = organisation!(root, "Banksia Rise")
    {_, wattle_admin} = member!(wattle, :administrator, root)
    {_, banksia_admin} = member!(banksia, :administrator, root)

    {wattle_card, _print} = Transfers.card(wattle)
    {banksia_card, _print} = Transfers.card(banksia)

    {:ok, banksia_there} =
      Transfers.record_remote_partner(wattle, banksia_card, actor: wattle_admin)

    {:ok, _wattle_there} =
      Transfers.record_remote_partner(banksia, wattle_card, actor: banksia_admin)

    {:ok,
     root: root,
     wattle: wattle,
     banksia: banksia,
     banksia_admin: banksia_admin,
     banksia_there: banksia_there}
  end

  # A transfer file from Wattle Creek with one journal entry that holds
  # `files`, each as `{name, type, bytes}`.
  defp file!(context, files) do
    named = for {name, type, bytes} <- files, do: {Ash.UUID.generate(), name, type, bytes}

    copy = %{
      "facts" => %{"name" => "Biscuit"},
      "medical" => [
        %{
          "kind" => "vaccination",
          "at" => DateTime.to_iso8601(DateTime.utc_now()),
          "files" =>
            for {id, name, type, bytes} <- named do
              %{"id" => id, "name" => name, "content_type" => type, "size" => byte_size(bytes)}
            end
        }
      ]
    }

    transfer = %{
      "export_id" => Ash.UUID.generate(),
      "from_refuge" => context.wattle.id,
      "to_refuge" => context.banksia.id,
      "copy" => copy
    }

    file =
      Archive.write(
        transfer,
        for({id, _name, _type, bytes} <- named, do: {id, bytes}),
        Keys.of(context.wattle),
        context.banksia_there
      )

    {file, for({id, name, _type, _bytes} <- named, into: %{}, do: {name, id})}
  end

  defp import!(context, file) do
    {:ok, imported} =
      Transfers.import_transfer(context.banksia, file, actor: context.banksia_admin)

    imported
  end

  defp reread(context, transfer) do
    {:ok, transfer} = Transfers.transfer(transfer.id, actor: context.banksia_admin)
    transfer
  end

  defp file_of(context, transfer, file_id),
    do:
      Transfers.transfer_file(context.banksia, transfer.id, file_id, actor: context.banksia_admin)

  defp work!, do: Oban.drain_queue(queue: :transfers)

  # A photo of a phone, with its GPS position, and data after its end.
  defp sent_photo, do: photo(gps: true) <> "<html><script>alert(1)</script></html>"

  test "the photos come out clean, with their size in the copy, and the files open after it",
       context do
    {file, ids} =
      file!(context, [
        {"card.jpg", "image/jpeg", sent_photo()},
        {"a.pdf", "application/pdf", pdf()}
      ])

    imported = import!(context, file)

    assert is_nil(imported.files_checked_at)
    assert {:error, :not_found} = file_of(context, imported, ids["card.jpg"])
    assert {:error, :not_found} = file_of(context, imported, ids["a.pdf"])
    refute Transfers.files_open?(imported)
    assert RescordWeb.TransferWords.files_check(imported) =~ "Rescord checks the files"

    assert %{success: 1} = work!()
    checked = reread(context, imported)
    assert %DateTime{} = checked.files_checked_at
    assert is_nil(checked.files_check_failure)
    assert Transfers.files_open?(checked)
    assert is_nil(RescordWeb.TransferWords.files_check(checked))

    assert {:ok, meta, bytes} = file_of(context, checked, ids["card.jpg"])
    assert Images.type_of(bytes) == "image/jpeg"
    refute bytes =~ "<html>"
    refute bytes =~ "Camera"
    assert meta["size"] == byte_size(bytes)

    assert {:ok, _meta, ^bytes} = file_of(context, checked, ids["card.jpg"])
    assert {:ok, _meta, pdf_bytes} = file_of(context, checked, ids["a.pdf"])
    assert pdf_bytes == pdf()
  end

  test "a copy with no file needs no check", context do
    {file, _ids} = file!(context, [])
    imported = import!(context, file)
    assert %DateTime{} = imported.files_checked_at
    assert %{success: 0} = work!()
  end

  test "a photo that libvips cannot read fails the check, and each file stays closed", context do
    broken = <<0xFF, 0xD8, 0xFF, 0xE0>> <> String.duplicate("x", 64)

    {file, ids} =
      file!(context, [{"a.pdf", "application/pdf", pdf()}, {"x.jpg", "image/jpeg", broken}])

    imported = import!(context, file)

    capture_log(fn -> assert %{success: 1} = work!() end)
    checked = reread(context, imported)
    assert checked.files_check_failure == :unreadable
    assert RescordWeb.TransferWords.files_check(checked) =~ "cannot be read"
    assert is_nil(checked.files_checked_at)
    assert {:error, :not_found} = file_of(context, checked, ids["a.pdf"])

    # The receiver cannot check such a copy again: the file is what it is.
    assert {:error, _stale} =
             Transfers.check_transfer_again(checked, actor: context.banksia_admin)
  end

  test "with the virus scan on, a harmful PDF fails the check", context do
    address = FakeClamd.start({:found, "Win.Test.EICAR_HDB-1"})
    {:ok, _settings} = Scan.save_settings(%{scan_on: true, address: address}, actor: context.root)

    {file, _ids} = file!(context, [{"a.pdf", "application/pdf", pdf()}])
    imported = import!(context, file)

    capture_log(fn -> assert %{success: 1} = work!() end)
    assert_received {:clamd_scanned, _bytes}
    assert reread(context, imported).files_check_failure == :infected
  end

  test "a clamd that does not answer makes the job try again, then the receiver checks again",
       context do
    {:ok, _settings} =
      Scan.save_settings(%{scan_on: true, address: FakeClamd.nobody()}, actor: context.root)

    {file, ids} = file!(context, [{"a.pdf", "application/pdf", pdf()}])
    imported = import!(context, file)

    capture_log(fn ->
      assert %{failure: 1} = work!()
      assert is_nil(reread(context, imported).files_check_failure)

      # The other tries of the job, until the last one.
      for _try <- 2..10, do: Oban.drain_queue(queue: :transfers, with_scheduled: true)
    end)

    failed = reread(context, imported)
    assert failed.files_check_failure == :unscanned
    assert RescordWeb.TransferWords.files_check(failed) =~ "Check them again"
    assert {:error, :not_found} = file_of(context, failed, ids["a.pdf"])

    {:ok, _settings} =
      Scan.save_settings(%{address: FakeClamd.start(:clean)}, actor: context.root)

    assert {:ok, _again} = Transfers.check_transfer_again(failed, actor: context.banksia_admin)
    assert %{success: 1} = work!()
    assert {:ok, _meta, _bytes} = file_of(context, reread(context, imported), ids["a.pdf"])
  end
end
