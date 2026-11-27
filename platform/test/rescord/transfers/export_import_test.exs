defmodule Rescord.Transfers.ExportImportTest do
  @moduledoc """
  Holds the transfers between two servers (ADR 0043): the partner card, a
  file that one refuge exports and the other imports, with its photos and
  PDFs, and each file that an import refuses.

  The two refuges are on one database here, as two servers would be: each
  knows the other only through the card that it recorded.

  Each test creates organisations, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.StorageFixtures

  alias Rescord.{Accounts, Journal, Photos, Transfers}
  alias Rescord.Transfers.{Archive, Keys, Snapshot}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    disk_store!(tmp_dir)
    root = root!()
    wattle = organisation!(root, "Wattle Creek")
    banksia = organisation!(root, "Banksia Rise")
    {_, wattle_admin} = member!(wattle, :administrator, root)
    {_, wattle_member} = member!(wattle, :member, wattle_admin)
    {_, banksia_admin} = member!(banksia, :administrator, root)
    {_, banksia_member} = member!(banksia, :member, banksia_admin)
    lists = lists!(wattle, root)
    wattle_options = [actor: wattle_admin, tenant: wattle]
    biscuit = resident!(lists, wattle_options)

    entry =
      Journal.write_entry!(
        %{resident_id: biscuit.id, kind: :vaccination, vaccine: "A sample vaccine"},
        wattle_options
      )

    {:ok, photo} =
      Journal.attach_file(
        %{entry_id: entry.id, name: "card.jpg", content: jpeg()},
        wattle_options
      )

    {:ok,
     root: root,
     wattle: wattle,
     banksia: banksia,
     wattle_admin: wattle_admin,
     wattle_member: wattle_member,
     banksia_admin: banksia_admin,
     banksia_member: banksia_member,
     biscuit: biscuit,
     photo: photo}
  end

  # Each refuge records the card of the other.
  defp partners!(context) do
    {wattle_card, _print} = Transfers.card(context.wattle)
    {banksia_card, _print} = Transfers.card(context.banksia)

    {:ok, banksia_there} =
      Transfers.record_remote_partner(context.wattle, banksia_card, actor: context.wattle_admin)

    {:ok, wattle_there} =
      Transfers.record_remote_partner(context.banksia, wattle_card, actor: context.banksia_admin)

    %{banksia_there: banksia_there, wattle_there: wattle_there}
  end

  defp export!(context, partner, extra \\ %{}) do
    %{
      organisation_id: context.wattle.id,
      remote_partner_id: partner.id,
      resident_id: context.biscuit.id
    }
    |> Map.merge(extra)
    |> Transfers.export_transfer(actor: context.wattle_admin)
  end

  # A photo with a caption and a photo of the journal, both in one album,
  # and the first as the profile picture.
  defp photos!(context) do
    options = [actor: context.wattle_admin, tenant: context.wattle]

    {:ok, added} =
      Photos.add_photo(
        %{resident_id: context.biscuit.id, content: photo(), caption: "On the lawn"},
        options
      )

    {:ok, adopted} = Photos.adopt(context.photo.id, options)

    {:ok, album} =
      Photos.make_album(%{resident_id: context.biscuit.id, name: "Surgery"}, options)

    for photo <- [added, adopted] do
      {:ok, _tie} = Photos.add_to_album(%{album_id: album.id, photo_id: photo.id}, options)
    end

    {:ok, _profile} = Photos.set_profile_photo(added, options)
    %{added: added, adopted: adopted}
  end

  # The part of a copy with the photos holds what `photos!/1` made, and
  # the refuge `organisation` has each file of it.
  defp assert_photos(transfer, organisation, actor, context, %{added: added}) do
    part = transfer.snapshot["photos"]
    assert %{"photos" => photos, "albums" => [album], "profile" => profile} = part
    assert profile == added.id

    assert [%{"caption" => "On the lawn"} = lawn] = Enum.filter(photos, &(&1["id"] == added.id))
    assert [of_journal] = Enum.reject(photos, &(&1["id"] == added.id))
    assert lawn["taken_on"] == Date.to_iso8601(added.taken_on)

    # The photo of the journal is the file of its entry, one time.
    assert [%{"files" => [%{"id" => file_id}]}] = transfer.snapshot["medical"]
    assert of_journal["id"] == file_id
    assert of_journal["id"] == context.photo.id

    assert album["name"] == "Surgery"
    assert Enum.sort(album["photos"]) == Enum.sort([added.id, file_id])

    for photo <- photos do
      assert {:ok, %{"content_type" => "image/jpeg"}, bytes} =
               Transfers.transfer_file(organisation, transfer.id, photo["id"], actor: actor)

      assert byte_size(bytes) == photo["size"]

      assert %{"id" => thumbnail_id, "content_type" => "image/webp", "size" => size} =
               photo["thumbnail"]

      assert {:ok, %{"content_type" => "image/webp"}, small} =
               Transfers.transfer_file(organisation, transfer.id, thumbnail_id, actor: actor)

      assert byte_size(small) == size
      assert <<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>> = small
    end
  end

  describe "the photos of a resident" do
    test "go to a refuge on another server with the part, and not without it", context do
      %{banksia_there: banksia_there} = partners!(context)
      made = photos!(context)

      assert {:ok, plain, _file} = export!(context, banksia_there)
      refute Map.has_key?(plain.snapshot, "photos")

      assert {:ok, exported, file} = export!(context, banksia_there, %{parts: [:photos]})
      assert exported.parts == [:photos]

      assert {:ok, imported} =
               Transfers.import_transfer(context.banksia, file, actor: context.banksia_admin)

      assert imported.parts == [:photos]
      {:ok, _accepted} = Transfers.accept_transfer(imported, actor: context.banksia_admin)
      assert_photos(imported, context.banksia, context.banksia_member, context, made)
    end

    test "go to a partner refuge on this server with the part", context do
      made = photos!(context)

      {:ok, asked} =
        Transfers.ask_partner(context.wattle, context.banksia.short_name,
          actor: context.wattle_admin
        )

      {:ok, _partnership} = Transfers.accept_partner(asked, actor: context.banksia_admin)

      assert {:ok, sent} =
               Transfers.send_transfer(
                 %{
                   organisation_id: context.wattle.id,
                   partner_id: context.banksia.id,
                   resident_id: context.biscuit.id,
                   parts: [:photos]
                 },
                 actor: context.wattle_admin
               )

      {:ok, _accepted} = Transfers.accept_transfer(sent, actor: context.banksia_admin)
      assert_photos(sent, context.banksia, context.banksia_member, context, made)
    end

    test "are refused in a file that does not hold a thumbnail that its copy names", context do
      %{banksia_there: banksia_there} = partners!(context)
      banksia_keys = Keys.of(context.banksia)
      {:ok, [wattle_there | _]} = Transfers.remote_partners_of(context.banksia, authorize?: false)
      photo_id = Ash.UUID.generate()
      bytes = stored_jpeg()

      transfer = %{
        "export_id" => Ash.UUID.generate(),
        "from_refuge" => context.wattle.id,
        "to_refuge" => context.banksia.id,
        "copy" => %{
          "facts" => %{"name" => "Biscuit"},
          "photos" => %{
            "photos" => [
              %{
                "id" => photo_id,
                "content_type" => "image/jpeg",
                "size" => byte_size(bytes),
                "thumbnail" => %{
                  "id" => Ash.UUID.generate(),
                  "content_type" => "image/webp",
                  "size" => 10
                }
              }
            ]
          }
        }
      }

      file = Archive.write(transfer, [{photo_id, bytes}], Keys.of(context.wattle), banksia_there)

      assert {:error, "has files that do not match its copy"} =
               Archive.read(file, context.banksia.id, banksia_keys, fn _ -> wattle_there end)
    end
  end

  describe "a partner card" do
    test "holds the id, the name and the two public keys, and no secret", context do
      {card, print} = Transfers.card(context.wattle)

      assert {:ok, read} = Keys.read_card(card)
      assert read.refuge_id == context.wattle.id
      assert read.name == "Wattle Creek"
      keys = Keys.of(context.wattle)
      assert read.sign_public == keys.sign_public
      refute card =~ Base.encode64(keys.sign_private)
      assert print == Keys.fingerprint(context.wattle)

      # The keys stay the same, and the private keys are encrypted at rest.
      assert Keys.of(context.wattle) == keys

      [record] =
        Ash.read!(Rescord.Transfers.RefugeKey, authorize?: false)
        |> Enum.filter(&(&1.organisation_id == context.wattle.id))

      refute record.sign_private == keys.sign_private
    end

    test "is recorded by a person with the power, one time, and never the own card", context do
      {wattle_card, _print} = Transfers.card(context.wattle)
      {banksia_card, banksia_print} = Transfers.card(context.banksia)

      assert {:error, %Ash.Error.Forbidden{}} =
               Transfers.record_remote_partner(context.wattle, banksia_card,
                 actor: context.wattle_member
               )

      assert {:ok, partner} =
               Transfers.record_remote_partner(context.wattle, banksia_card,
                 actor: context.wattle_admin
               )

      assert partner.name == "Banksia Rise"
      assert partner.fingerprint == banksia_print

      for {card, words} <- [
            {banksia_card, "Card is the card of a partner that this refuge recorded"},
            {wattle_card, "Card is the card of this refuge"},
            {"RESCORD-PARTNER-1.bm90IGEgY2FyZA", "Card is not a partner card of Rescord"}
          ] do
        assert {:error, %Ash.Error.Invalid{} = error} =
                 Transfers.record_remote_partner(context.wattle, card,
                   actor: context.wattle_admin
                 )

        assert Accounts.error_messages(error) == [words]
      end

      # Each member reads the partners, and nobody of another refuge does.
      assert {:ok, [_]} =
               Transfers.remote_partners_of(context.wattle, actor: context.wattle_member)

      assert {:ok, []} =
               Transfers.remote_partners_of(context.wattle, actor: context.banksia_admin)
    end
  end

  describe "a transfer file" do
    test "goes from one refuge to the other, with its photos, and waits for an answer", context do
      %{banksia_there: banksia_there} = partners!(context)

      assert {:ok, exported, file} = export!(context, banksia_there, %{note: "Shy at first."})
      assert exported.state == :exported
      assert exported.remote_partner_id == banksia_there.id
      assert is_nil(exported.to_organisation_id)
      assert <<"RSCD", 1, _rest::binary>> = file
      # Nothing of the resident can be read in the file.
      refute file =~ "Biscuit"
      refute file =~ "A sample vaccine"

      assert {:ok, imported} =
               Transfers.import_transfer(context.banksia, file, actor: context.banksia_admin)

      assert imported.state == :sent
      assert imported.export_id == exported.id
      assert imported.resident_name == "Biscuit"
      assert imported.note == "Shy at first."
      assert is_nil(imported.from_organisation_id)

      assert [%{"facts" => %{"vaccine" => "A sample vaccine"}, "files" => [file_meta]}] =
               imported.snapshot["medical"]

      assert file_meta["name"] == "card.jpg"

      # The members there see it after the answer, with its photo.
      assert {:ok, nil} =
               Transfers.transfer_of(context.banksia, imported.id, actor: context.banksia_member)

      {:ok, _accepted} = Transfers.accept_transfer(imported, actor: context.banksia_admin)

      assert {:ok, %{"name" => "card.jpg"}, bytes} =
               Transfers.transfer_file(context.banksia, imported.id, file_meta["id"],
                 actor: context.banksia_member
               )

      assert bytes == stored_jpeg()

      # The refuge that sent it reads its record of the export.
      assert {:ok, [%{state: :exported}]} =
               Transfers.transfers_of(context.wattle, actor: context.wattle_member)
    end

    test "imports one time", context do
      %{banksia_there: banksia_there} = partners!(context)
      {:ok, _exported, file} = export!(context, banksia_there)

      assert {:ok, _imported} =
               Transfers.import_transfer(context.banksia, file, actor: context.banksia_admin)

      assert {:error, %Ash.Error.Invalid{} = error} =
               Transfers.import_transfer(context.banksia, file, actor: context.banksia_admin)

      assert hd(Accounts.error_messages(error)) =~ "imported already"
    end

    test "is refused from a refuge that is not a recorded partner, or that ended", context do
      {banksia_card, _print} = Transfers.card(context.banksia)

      {:ok, banksia_there} =
        Transfers.record_remote_partner(context.wattle, banksia_card, actor: context.wattle_admin)

      {:ok, _exported, file} = export!(context, banksia_there)

      # Banksia did not record the card of Wattle Creek.
      assert {:error, %Ash.Error.Invalid{} = error} =
               Transfers.import_transfer(context.banksia, file, actor: context.banksia_admin)

      assert Accounts.error_messages(error) == [
               "File comes from a refuge that is not a partner of this one"
             ]

      {wattle_card, _print} = Transfers.card(context.wattle)

      {:ok, wattle_there} =
        Transfers.record_remote_partner(context.banksia, wattle_card,
          actor: context.banksia_admin
        )

      {:ok, _ended} = Transfers.end_remote_partner(wattle_there, actor: context.banksia_admin)

      assert {:error, %Ash.Error.Invalid{}} =
               Transfers.import_transfer(context.banksia, file, actor: context.banksia_admin)
    end

    test "is refused when it changed, when it is for another refuge, or when it is not one",
         context do
      %{banksia_there: banksia_there} = partners!(context)
      {:ok, _exported, file} = export!(context, banksia_there)

      size = byte_size(file) - 1
      <<head::binary-size(size), last>> = file
      changed = head <> <<Bitwise.bxor(last, 1)>>

      third = organisation!(context.root, "Third")
      {_, third_admin} = member!(third, :administrator, context.root)
      {wattle_card, _print} = Transfers.card(context.wattle)
      {:ok, _} = Transfers.record_remote_partner(third, wattle_card, actor: third_admin)

      for {organisation, actor, bytes, words} <- [
            {context.banksia, context.banksia_admin, changed,
             "changed on its way, or it is not for this refuge"},
            {third, third_admin, file, "is for another refuge"},
            {context.banksia, context.banksia_admin, "not a file",
             "is not a transfer file of Rescord"}
          ] do
        assert {:error, %Ash.Error.Invalid{} = error} =
                 Transfers.import_transfer(organisation, bytes, actor: actor)

        assert Accounts.error_messages(error) == ["File " <> words]
      end
    end

    test "is refused when its inside names another refuge than its signed header", context do
      partners!(context)
      wattle_keys = Keys.of(context.wattle)
      {:ok, [banksia_there | _]} = Transfers.remote_partners_of(context.wattle, authorize?: false)
      export_id = Ash.UUID.generate()

      # The inside says that a third refuge sent it.
      inside = %{
        "export_id" => export_id,
        "from_refuge" => Ash.UUID.generate(),
        "to_refuge" => context.banksia.id,
        "copy" => %{"facts" => %{"name" => "Biscuit"}}
      }

      {:ok, {_name, zip}} =
        :zip.create(~c"x.zip", [{~c"transfer.json", Jason.encode!(inside)}], [:memory])

      sealed =
        Rescord.Transfers.Crypto.seal(
          zip,
          %{
            "format" => "rescord-transfer",
            "version" => 1,
            "export_id" => export_id,
            "from_refuge" => context.wattle.id,
            "to_refuge" => context.banksia.id
          },
          wattle_keys.sign_private,
          banksia_there.box_public
        )

      file =
        <<"RSCD", 1, byte_size(sealed.header)::32, sealed.header::binary,
          byte_size(sealed.signature)::16, sealed.signature::binary, sealed.payload::binary>>

      assert {:error, %Ash.Error.Invalid{} = error} =
               Transfers.import_transfer(context.banksia, file, actor: context.banksia_admin)

      assert Accounts.error_messages(error) == ["File is not a transfer file of Rescord"]
    end

    test "names its files exactly, each with its size and its type", context do
      %{banksia_there: banksia_there} = partners!(context)
      wattle_keys = Keys.of(context.wattle)
      banksia_keys = Keys.of(context.banksia)
      {:ok, wattle_there} = Transfers.remote_partners_of(context.banksia, authorize?: false)
      wattle_there = hd(wattle_there)

      copy = %{
        "facts" => %{"name" => "Biscuit"},
        "medical" => [
          %{
            "kind" => "vaccination",
            "at" => DateTime.to_iso8601(DateTime.utc_now()),
            "files" => [
              %{
                "id" => Ash.UUID.generate(),
                "name" => "x.jpg",
                "content_type" => "image/jpeg",
                "size" => 4
              }
            ]
          }
        ]
      }

      transfer = %{
        "export_id" => Ash.UUID.generate(),
        "from_refuge" => context.wattle.id,
        "to_refuge" => context.banksia.id,
        "copy" => copy
      }

      # The copy names a file that the file does not hold.
      file = Archive.write(transfer, [], wattle_keys, banksia_there)

      assert {:error, "has files that do not match its copy"} =
               Archive.read(file, context.banksia.id, banksia_keys, fn _ -> wattle_there end)
    end

    test "is exported by a person with the power, for a partner that this refuge recorded",
         context do
      %{banksia_there: banksia_there, wattle_there: wattle_there} = partners!(context)

      assert {:error, %Ash.Error.Forbidden{}} =
               Transfers.export_transfer(
                 %{
                   organisation_id: context.wattle.id,
                   remote_partner_id: banksia_there.id,
                   resident_id: context.biscuit.id
                 },
                 actor: context.wattle_member
               )

      # A partner that another refuge recorded is not one of this refuge.
      assert {:error, %Ash.Error.Invalid{} = error} = export!(context, wattle_there)

      assert Accounts.error_messages(error) == [
               "Remote partner is not a partner of this refuge on another server"
             ]

      {:ok, _ended} = Transfers.end_remote_partner(banksia_there, actor: context.wattle_admin)
      assert {:error, %Ash.Error.Invalid{}} = export!(context, banksia_there)
    end

    test "is imported by a person with the power", context do
      %{banksia_there: banksia_there} = partners!(context)
      {:ok, _exported, file} = export!(context, banksia_there)

      assert {:error, %Ash.Error.Forbidden{}} =
               Transfers.import_transfer(context.banksia, file, actor: context.banksia_member)

      # Nor in the name of a refuge that the person does not belong to.
      assert {:error, %Ash.Error.Forbidden{}} =
               Transfers.import_transfer(context.banksia, file, actor: context.wattle_admin)
    end
  end

  describe "a copy from another server" do
    test "keeps only the keys and the types that Rescord knows" do
      assert {:ok, clean} =
               Snapshot.clean(%{
                 "facts" => %{
                   "name" => "Biscuit",
                   "species" => %{"a" => "map"},
                   "born_on" => "not a date",
                   "arrived_on" => "2026-01-02",
                   "breeds" => ["Sheltie", 3, %{}],
                   "secret" => "dropped"
                 },
                 "medical" => [
                   %{
                     "kind" => "diagnosis",
                     "at" => "yesterday",
                     "facts" => %{"condition" => "Cold", "x" => 1}
                   },
                   "not an entry"
                 ],
                 "stay" => %{"arrival" => %{"kind" => "surrender", "on" => "2026-01-02"}},
                 "unknown" => %{}
               })

      assert clean["facts"]["name"] == "Biscuit"
      assert clean["facts"]["species"] == nil
      assert clean["facts"]["born_on"] == nil
      assert clean["facts"]["arrived_on"] == "2026-01-02"
      assert clean["facts"]["breeds"] == ["Sheltie"]
      refute Map.has_key?(clean["facts"], "secret")

      assert [%{"kind" => "diagnosis", "at" => nil, "facts" => %{"condition" => "Cold"}}] =
               clean["medical"]

      refute Map.has_key?(hd(clean["medical"])["facts"], "x")
      assert clean["stay"]["arrival"]["on"] == "2026-01-02"
      refute Map.has_key?(clean, "unknown")

      assert Snapshot.clean(%{"no" => "facts"}) == :error
      assert Snapshot.clean("text") == :error
    end

    test "keeps the photos that are images, and the albums and the profile that name them" do
      [one, two, small] = for _ <- 1..3, do: Ash.UUID.generate()
      image = %{"content_type" => "image/jpeg", "size" => 10}

      assert {:ok, %{"photos" => part}} =
               Snapshot.clean(%{
                 "facts" => %{"name" => "Biscuit"},
                 "photos" => %{
                   "photos" => [
                     Map.merge(image, %{
                       "id" => one,
                       "caption" => "On the lawn",
                       "taken_on" => "2026-10-03",
                       "thumbnail" => %{
                         "id" => small,
                         "content_type" => "image/webp",
                         "size" => 4
                       },
                       "key" => "dropped"
                     }),
                     Map.merge(image, %{"id" => one, "caption" => "The same id again"}),
                     Map.merge(image, %{"id" => two, "taken_on" => "no date", "thumbnail" => "x"}),
                     %{"id" => Ash.UUID.generate(), "content_type" => "text/html", "size" => 10},
                     %{"id" => "no id", "content_type" => "image/png", "size" => 10},
                     "not a photo"
                   ],
                   "albums" => [
                     %{"name" => "Surgery", "photos" => [one, one, Ash.UUID.generate(), 3]},
                     %{"photos" => [one]},
                     "not an album"
                   ],
                   "profile" => Ash.UUID.generate()
                 }
               })

      assert [
               %{
                 "id" => ^one,
                 "caption" => "On the lawn",
                 "taken_on" => "2026-10-03",
                 "thumbnail" => %{"id" => ^small, "content_type" => "image/webp", "size" => 4}
               } = first,
               %{"id" => ^two, "caption" => nil, "taken_on" => nil, "thumbnail" => nil}
             ] = part["photos"]

      refute Map.has_key?(first, "key")
      assert part["albums"] == [%{"name" => "Surgery", "photos" => [one]}]
      assert part["profile"] == nil

      # A part that is no map is a part with no photo.
      assert {:ok, %{"photos" => %{"photos" => [], "albums" => [], "profile" => nil}}} =
               Snapshot.clean(%{"facts" => %{}, "photos" => "text"})
    end
  end
end
