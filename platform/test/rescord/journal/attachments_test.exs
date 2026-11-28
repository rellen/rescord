defmodule Rescord.Journal.AttachmentsTest do
  @moduledoc """
  Holds the attachments of the journal (ADR 0041): the type that the first
  bytes give, the limits of a file, the key of the file in the store, who
  attaches, reads and removes a file, and the answer when the store fails.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.StorageFixtures

  alias Rescord.Journal
  alias Rescord.Journal.Changes.StoreAttachment
  alias Rescord.Storage.Errors.RefusedFile

  doctest StoreAttachment

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    disk_store!(tmp_dir)
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    {_, other} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    options = [actor: member, tenant: organisation]
    biscuit = resident!(lists, options)

    entry =
      Journal.write_entry!(
        %{resident_id: biscuit.id, kind: :general, note: "Weighed and checked."},
        options
      )

    {:ok,
     root: root,
     tmp_dir: tmp_dir,
     organisation: organisation,
     administrator: administrator,
     member: member,
     other: other,
     options: options,
     entry: entry}
  end

  defp attach(context, content, extra \\ %{}, options \\ nil) do
    %{entry_id: context.entry.id, name: "biscuit.jpg", content: content}
    |> Map.merge(extra)
    |> Journal.attach_file(options || context.options)
  end

  describe "a file of an entry" do
    test "has the type of its first bytes, its size, and a key of the organisation", context do
      assert {:ok, attachment} = attach(context, jpeg(), %{name: "  biscuit.png  "})

      assert attachment.content_type == "image/jpeg"
      assert attachment.size == byte_size(stored_jpeg())
      assert attachment.name == "biscuit.png"
      assert attachment.author_id == context.member.id
      assert attachment.key == "#{context.organisation.id}/attachments/#{attachment.id}"
      assert File.read!(Path.join(context.tmp_dir, attachment.key)) == stored_jpeg()

      assert {:ok, %{} = same, bytes} = Journal.attachment_file(attachment.id, context.options)
      assert same.id == attachment.id
      assert bytes == stored_jpeg()

      assert {:ok, %{} = by_entry} = Journal.attachments_of([context.entry.id], context.options)
      assert [%{id: id}] = by_entry[context.entry.id]
      assert id == attachment.id
    end

    test "is a photo or a PDF, and not empty, and 20 MB at most", context do
      assert {:ok, %{content_type: "application/pdf"}} = attach(context, pdf())

      for {content, reason, words} <- [
            {"<html><script></script>", :not_a_photo_or_pdf, "Content is not a photo or a PDF"},
            {"", :empty, "Content is an empty file"},
            {<<0xFF, 0xD8, 0xFF>> <> :binary.copy("a", StoreAttachment.max_size()), :too_large,
             "Content is more than 20 MB"}
          ] do
        # A Splode error of Rescord is an error of the class invalid of Ash
        # (ADR 0077, E2), and keeps its reason and its field.
        assert {:error, %Ash.Error.Invalid{errors: errors} = error} = attach(context, content)
        assert [%RefusedFile{reason: ^reason, field: :content}] = errors
        assert hd(Rescord.Accounts.error_messages(error)) =~ words
      end

      # Only the PDF is there.
      assert {:ok, %{} = by_entry} = Journal.attachments_of([context.entry.id], context.options)
      assert [%{content_type: "application/pdf"}] = by_entry[context.entry.id]
    end

    test "names an entry of this journal", context do
      assert {:error, %Ash.Error.Invalid{} = error} =
               attach(context, jpeg(), %{entry_id: Ash.UUID.generate()})

      assert Rescord.Accounts.error_messages(error) == ["Entry is not an entry of this journal"]
    end

    test "takes no type, size, key or author as input", context do
      for extra <- [
            %{content_type: "text/html"},
            %{size: 1},
            %{key: "x"},
            %{author_id: context.other.id}
          ] do
        assert {:error, %Ash.Error.Invalid{}} = attach(context, jpeg(), extra)
      end
    end

    test "is not written when the store refuses the file", context do
      Shoddy.Tests.put_app_env(:rescord, :storage, __MODULE__.DownStore)

      assert {:error, %Ash.Error.Invalid{} = error} = attach(context, jpeg())

      assert Rescord.Accounts.error_messages(error) == [
               "Content did not reach the store. Try again later"
             ]

      assert {:ok, map} = Journal.attachments_of([context.entry.id], context.options)
      assert map == %{}
    end
  end

  describe "who works with the files" do
    test "each member reads them, and nobody outside the organisation", context do
      {:ok, attachment} = attach(context, jpeg())
      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)

      assert {:ok, _, _} =
               Journal.attachment_file(attachment.id,
                 actor: context.other,
                 tenant: context.organisation
               )

      for actor <- [outsider, nil] do
        assert {:error, _} =
                 Journal.attachment_file(attachment.id,
                   actor: actor,
                   tenant: context.organisation
                 )

        assert {:error, %Ash.Error.Forbidden{}} =
                 attach(context, jpeg(), %{}, actor: actor, tenant: context.organisation)
      end
    end

    test "a member takes off their own file, and an administrator each file", context do
      {:ok, own} = attach(context, jpeg())

      {:ok, theirs} =
        attach(context, pdf(), %{}, actor: context.other, tenant: context.organisation)

      assert Journal.can_remove_attachment?(:member, context.member, own)
      refute Journal.can_remove_attachment?(:member, context.member, theirs)
      assert Journal.can_remove_attachment?(:administrator, context.member, theirs)

      assert {:error, %Ash.Error.Forbidden{}} = Journal.remove_attachment(theirs, context.options)
      assert :ok = Journal.remove_attachment(own, context.options)

      assert :ok =
               Journal.remove_attachment(theirs,
                 actor: context.administrator,
                 tenant: context.organisation
               )

      assert Journal.attachments_of([context.entry.id], context.options) == {:ok, %{}}
      # The file stays in the store: the history can name it.
      assert File.exists?(Path.join(context.tmp_dir, own.key))
    end

    test "is a relationship of its entry, in the order of the upload (ADR 0092)", context do
      resident_id = context.entry.resident_id
      {:ok, first} = attach(context, jpeg(), %{name: "first.jpg"})
      {:ok, second} = attach(context, pdf(), %{name: "second.pdf"})

      files = fn options ->
        [entry] = resident_id |> Journal.query_to_journal(options) |> Ash.read!()
        Enum.map(entry.attachments, & &1.name)
      end

      assert files.(context.options) == ["first.jpg", "second.pdf"]

      # One file of the journal of the resident, by its id.
      assert {:ok, %{name: "first.jpg"}} =
               Journal.attachment_of(resident_id, first.id, context.options)

      assert {:ok, nil} =
               Journal.attachment_of(Ash.UUID.generate(), first.id, context.options)

      assert {:ok, nil} =
               Journal.attachment_of(resident_id, Ash.UUID.generate(), context.options)

      # A file that is removed is not there.
      assert :ok = Journal.remove_attachment(second, context.options)
      assert files.(context.options) == ["first.jpg"]
      assert {:ok, nil} = Journal.attachment_of(resident_id, second.id, context.options)
    end
  end

  defmodule DownStore do
    @moduledoc "A store that is down: it refuses each file."
    @behaviour Rescord.Storage

    @impl true
    def put(_key, _bytes, _type), do: {:error, :down}
    @impl true
    def get(_key), do: {:error, :down}
    @impl true
    def delete(_key), do: {:error, :down}
    @impl true
    def list, do: {:error, :down}
    @impl true
    def files, do: {:error, :down}
  end
end
