defmodule Rescord.Storage.CompareTest do
  @moduledoc """
  Holds the comparison of the list of the store with the keys that the
  records name (ADR 0091): the group of each file, the files that are
  missing, the second question to the store for each of those, and the
  words of the report. `Rescord.Release.FilesTest` holds the read of the
  store and the database.
  """

  use ExUnit.Case, async: true

  alias Rescord.Storage.{Compare, Disk}

  @files [
    {"lost+found", 0},
    {"check/probe/0a1b", 26},
    {"org-1/attachments/a", 1_000},
    {"org-1/photos/b", 2_000_000},
    {"org-1/photos/b.part-0a1b2c3d", 4},
    {"org-1/photos/left", 300},
    {"org-1/thumbnails/b", 5_000},
    {"org-2/transfers/t1/left", 700},
    {"org-9/photos/c", 50}
  ]

  @named %{
    "org-1" => [
      {"org-1/attachments/a", "journal attachment", "a"},
      # A photo of a journal entry names the file of its attachment.
      {"org-1/attachments/a", "photo", "p"},
      {"org-1/photos/b", "photo", "b"},
      {"org-1/thumbnails/b", "photo", "b"},
      {"org-1/photos/gone", "photo", "gone"},
      {"org-1/attachments/gone", "photo", "q"},
      {"org-1/attachments/gone", "journal attachment", "gone"}
    ],
    "org-2" => [{"org-2/transfers/t2/f1", "transfer", "t2"}],
    # An organisation with no file.
    "org-3" => []
  }

  describe "the comparison" do
    test "puts each file of the store in one group, and sums the sizes" do
      report = Compare.run(@files, @named)

      assert report.store == %{count: 9, bytes: 2_007_080}
      assert report.organisations == 3
      assert report.named == %{count: 3, bytes: 2_006_000}
      assert report.leftover == [{"org-1/photos/left", 300}, {"org-2/transfers/t1/left", 700}]
      assert report.unknown == [{"check/probe/0a1b", 26}, {"org-9/photos/c", 50}]
      assert report.other == [{"lost+found", 0}, {"org-1/photos/b.part-0a1b2c3d", 4}]
    end

    test "names each key that the store does not list, with its records, one time" do
      report = Compare.run(@files, @named)

      assert report.missing == [
               {"org-1/attachments/gone", "org-1",
                [{"journal attachment", "gone"}, {"photo", "q"}], :not_found},
               {"org-1/photos/gone", "org-1", [{"photo", "gone"}], :not_found},
               {"org-2/transfers/t2/f1", "org-2", [{"transfer", "t2"}], :not_found}
             ]

      refute Compare.complete?(report)
    end

    test "decides by the records, and not by the shape of a key" do
      # A key with the shape of a photo and no record is a leftover, and a
      # record can name a key of any shape.
      report =
        Compare.run(
          [{"org-1/photos/x", 1}, {"org-1/anything/else/y", 2}],
          %{"org-1" => [{"org-1/anything/else/y", "photo", "y"}]}
        )

      assert report.named == %{count: 1, bytes: 2}
      assert report.leftover == [{"org-1/photos/x", 1}]
      assert Compare.complete?(report)
    end

    test "has nothing to say of an empty store and no organisation" do
      report = Compare.run([], %{})
      assert report == %Compare{}
      assert Compare.complete?(report)
    end
  end

  describe "the second question to the store" do
    test "counts a file that arrived after the list as named, and keeps the others" do
      get = fn
        "org-1/photos/gone" -> {:ok, "a photo of an upload that ended a moment ago"}
        "org-1/attachments/gone" -> {:error, :not_found}
        "org-2/transfers/t2/f1" -> {:error, {:status, 503}}
      end

      report = @files |> Compare.run(@named) |> Compare.confirm(get)

      assert report.named == %{count: 4, bytes: 2_006_044}
      assert report.store == %{count: 10, bytes: 2_007_124}

      assert report.missing == [
               {"org-1/attachments/gone", "org-1",
                [{"journal attachment", "gone"}, {"photo", "q"}], :not_found},
               {"org-2/transfers/t2/f1", "org-2", [{"transfer", "t2"}], {:status, 503}}
             ]
    end

    test "asks for no file when none is missing" do
      report =
        Compare.run([{"org-1/photos/b", 1}], %{"org-1" => [{"org-1/photos/b", "photo", "b"}]})

      assert Compare.confirm(report, fn _key -> flunk("the store was asked") end) == report
    end
  end

  describe "the report in words" do
    setup do
      previous = Application.get_env(:rescord, Disk)
      Application.put_env(:rescord, Disk, root: "/var/lib/rescord/files")
      on_exit(fn -> Application.put_env(:rescord, Disk, previous) end)
    end

    test "says each group with its size, and names the files" do
      get = fn
        "org-2/transfers/t2/f1" -> {:error, {:status, 503}}
        _key -> {:error, :not_found}
      end

      words = @files |> Compare.run(@named) |> Compare.confirm(get) |> Compare.format(Disk)

      assert words == """
             The directory /var/lib/rescord/files has 9 files (2.0 MB), and Rescord has 3 organisations.

             named     3 files (2.0 MB) that a record names
             leftover  2 files (1.0 kB) that no record names
               org-1/photos/left  300 B
               org-2/transfers/t1/left  700 B
             unknown   2 files (76 B) of no organisation of this server
               check/probe/0a1b  26 B
               org-9/photos/c  50 B
             other     2 that Rescord did not put there: lost+found, org-1/photos/b.part-0a1b2c3d
             FAIL      3 files that a record names, and that the store does not have
               org-1/attachments/gone: journal attachment gone and photo q, of the organisation org-1
               org-1/photos/gone: photo gone, of the organisation org-1
               org-2/transfers/t2/f1: transfer t2, of the organisation org-2. The store did not say whether it is there: the service answered 503

             A leftover is a file that an upload or a transfer put in the store before it failed.
             A file of an upload that runs now can be in this list too. Run the command
             again: a leftover is in both runs.
             The store does not have each file that a record names: look for each FAIL in
             a backup of the store. A page that shows such a file gives an error.
             Nothing was changed.\
             """
    end

    test "is short for a store with no leftover and no missing file" do
      words =
        [{"org-1/photos/b", 1_500}]
        |> Compare.run(%{"org-1" => [{"org-1/photos/b", "photo", "b"}]})
        |> Compare.format(Disk)

      assert words == """
             The directory /var/lib/rescord/files has 1 file (1.5 kB), and Rescord has 1 organisation.

             named     1 file (1.5 kB) that a record names

             The store has each file that a record names.
             Nothing was changed.\
             """
    end

    test "names the first 20 files of a group, and each one when asked" do
      files = for number <- 1..23, do: {"org-1/photos/#{100 + number}", 10}
      named = for number <- 1..22, do: {"org-1/photos/#{200 + number}", "photo", "#{number}"}

      report =
        Compare.run(files ++ [{"a", 1}, {"b", 1}, {"c", 1}, {"d", 1}, {"e", 1}, {"f", 1}], %{
          "org-1" => named
        })

      words = Compare.format(report, Disk)

      assert words =~
               "leftover  23 files (230 B) that no record names\n  org-1/photos/101  10 B\n"

      assert words =~
               "  org-1/photos/120  10 B\n  and 3 more: bin/check-files --all prints each one\n"

      refute words =~ "org-1/photos/121"

      assert words =~
               "  org-1/photos/220: photo 20, of the organisation org-1\n  and 2 more: bin/check-files"

      refute words =~ "org-1/photos/221"
      assert words =~ "other     6 that Rescord did not put there: a, b, c, d, e, and 1 more\n"

      words = Compare.format(report, Disk, all: true)
      assert words =~ "  org-1/photos/123  10 B\n"
      assert words =~ "  org-1/photos/222: photo 22, of the organisation org-1\n"
      refute words =~ "more: bin/check-files"
    end

    test "says why the comparison could not be made" do
      assert Compare.format_fault({:list, {:eacces, "/var/lib/rescord/files"}}, Disk) ==
               "Rescord cannot list the files of the directory /var/lib/rescord/files: " <>
                 "permission denied: /var/lib/rescord/files.\nNothing was compared."

      assert Compare.format_fault({:database, "connection refused"}, Disk) ==
               "Rescord cannot read the database: connection refused.\nNothing was compared."

      assert Compare.format_fault({:migrations, "2 have not run: the next start runs them"}, Disk) =~
               "of the migrations, 2 have not run"
    end
  end
end
