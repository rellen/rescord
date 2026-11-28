defmodule Rescord.StorageTest do
  @moduledoc """
  Holds the stores of files (ADR 0038): the key of a file, the store in a
  directory that the tests use, and the requests that the store of S3
  signs, which a stub of `Req.Test` reads in place of a service. Each
  store lists its files (ADR 0059).

  The tests change the configuration of the application, so they do not
  run beside others.
  """

  use ExUnit.Case, async: false

  alias Rescord.Storage
  alias Rescord.Storage.{Disk, S3}

  doctest Storage

  describe "a key" do
    test "is made of ids and words, and nothing that leaves the store" do
      assert Storage.key("org-1", ["attachments", "abc"]) == "org-1/attachments/abc"

      for bad <- ["..", "a/b", "", "a b", String.duplicate("a", 65)] do
        assert_raise ArgumentError, fn -> Storage.key("org-1", ["attachments", bad]) end
      end
    end

    test "is known from a name that Rescord did not make" do
      assert Storage.key?("org-1/attachments/abc")
      assert Storage.key?("org-1/transfers/t1/f1")

      for name <- ~w(org-1 lost+found org-1/photos/abc.part-0a1b ../outside /etc/passwd
                     org-1//abc org-1/photos/ probe.txt) ++ ["", "org-1/a b"] do
        refute Storage.key?(name), name
      end
    end
  end

  test "a store says what it is, with no key and no secret" do
    Shoddy.Tests.put_app_env(:rescord, S3,
      endpoint: "https://t3.storage.dev",
      bucket: "rescord",
      access_key_id: "the-key-id",
      secret_access_key: "the-secret"
    )

    assert Storage.describe(S3) == "the bucket rescord at https://t3.storage.dev"
    assert Storage.describe(Disk) =~ ~r/^the directory /
  end

  describe "the store in a directory" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      Shoddy.Tests.put_app_env(:rescord, Disk, root: tmp_dir)
    end

    test "puts, gets and deletes a file", %{tmp_dir: tmp_dir} do
      key = Storage.key("org-1", ["attachments", "abc"])

      assert Disk.get(key) == {:error, :not_found}
      assert :ok = Disk.put(key, "bytes", "application/pdf")
      assert File.read!(Path.join(tmp_dir, key)) == "bytes"
      assert Disk.get(key) == {:ok, "bytes"}
      assert :ok = Disk.delete(key)
      assert Disk.get(key) == {:error, :not_found}
      # A key with no file is no error.
      assert :ok = Disk.delete(key)
    end

    test "refuses a key that leaves the directory" do
      assert_raise ArgumentError, fn -> Disk.put("../outside", "bytes", "text/plain") end
      assert_raise ArgumentError, fn -> Disk.get("/etc/passwd") end
    end

    test "a put leaves the file under its key, and nothing beside it", %{tmp_dir: tmp_dir} do
      assert :ok = Disk.put("org-1/attachments/abc", "bytes", "application/pdf")
      assert File.ls!(Path.join(tmp_dir, "org-1/attachments")) == ["abc"]
    end

    test "a put that fails leaves no part of a file", %{tmp_dir: tmp_dir} do
      # A directory under the key, so the file cannot take its name.
      File.mkdir_p!(Path.join(tmp_dir, "org-1/attachments/abc"))

      assert {:error, _reason} = Disk.put("org-1/attachments/abc", "bytes", "application/pdf")
      assert File.ls!(Path.join(tmp_dir, "org-1/attachments")) == ["abc"]
    end

    test "lists each file by its key, in order", %{tmp_dir: tmp_dir} do
      assert Disk.list() == {:ok, []}

      for key <- ["org-2/photos/b", "org-1/transfers/t1/f1", "org-1/attachments/a"] do
        :ok = Disk.put(key, "bytes", "image/jpeg")
      end

      File.mkdir_p!(Path.join(tmp_dir, "org-3/photos"))

      assert Disk.list() ==
               {:ok, ["org-1/attachments/a", "org-1/transfers/t1/f1", "org-2/photos/b"]}
    end

    test "lists a name that is no key, and does not open a directory with such a name",
         %{tmp_dir: tmp_dir} do
      :ok = Disk.put("org-1/attachments/a", "bytes", "image/jpeg")
      File.write!(Path.join(tmp_dir, "org-1/attachments/a.part-0a1b2c3d"), "half")
      File.mkdir_p!(Path.join(tmp_dir, "lost+found"))
      File.write!(Path.join(tmp_dir, "lost+found/inode"), "bytes")
      # A directory that nobody reads is no fault when its name is no part of a key.
      File.chmod!(Path.join(tmp_dir, "lost+found"), 0o000)
      on_exit(fn -> File.chmod(Path.join(tmp_dir, "lost+found"), 0o755) end)

      assert Disk.list() ==
               {:ok, ["lost+found", "org-1/attachments/a", "org-1/attachments/a.part-0a1b2c3d"]}
    end

    test "lists each file with its size, and reads no file for it", %{tmp_dir: tmp_dir} do
      assert Disk.files() == {:ok, []}

      :ok = Disk.put("org-1/attachments/a", "five!", "image/jpeg")
      :ok = Disk.put("org-1/photos/b", String.duplicate("b", 2_000), "image/jpeg")
      :ok = Disk.put("org-2/photos/empty", "", "image/jpeg")
      File.write!(Path.join(tmp_dir, "org-1/attachments/a.part-0a1b2c3d"), "half")
      File.mkdir_p!(Path.join(tmp_dir, "lost+found"))
      # A file that nobody reads has a size all the same.
      File.chmod!(Path.join(tmp_dir, "org-1/photos/b"), 0o000)

      assert Disk.files() ==
               {:ok,
                [
                  {"lost+found", 0},
                  {"org-1/attachments/a", 5},
                  {"org-1/attachments/a.part-0a1b2c3d", 4},
                  {"org-1/photos/b", 2_000},
                  {"org-2/photos/empty", 0}
                ]}

      # The names are those of the list.
      {:ok, files} = Disk.files()
      assert Disk.list() == {:ok, Enum.map(files, &elem(&1, 0))}
    end

    test "says which directory it cannot read", %{tmp_dir: tmp_dir} do
      missing = Path.join(tmp_dir, "none")
      Shoddy.Tests.put_app_env(:rescord, Disk, root: missing)
      assert Disk.list() == {:error, {:enoent, missing}}

      file = Path.join(tmp_dir, "a-file")
      File.write!(file, "")
      Shoddy.Tests.put_app_env(:rescord, Disk, root: file)
      assert Disk.list() == {:error, {:enotdir, file}}
      assert Disk.files() == {:error, {:enotdir, file}}
    end
  end

  describe "the store of S3" do
    setup do
      Shoddy.Tests.put_app_env(:rescord, S3,
        endpoint: "http://garage.test:3900",
        region: "garage",
        bucket: "rescord",
        access_key_id: "GK0000000000000000000000ad",
        secret_access_key: "000000000000000000000000000000000000000000000000000000000000dec0",
        req_options: [plug: {Req.Test, S3}, retry: false]
      )
    end

    test "puts a file in the bucket, in the path, with its type and a signature" do
      test = self()

      Req.Test.stub(S3, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test, {:request, conn, body})
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert :ok = S3.put("org-1/attachments/abc", "bytes", "image/png")
      assert_received {:request, conn, "bytes"}

      assert conn.method == "PUT"
      assert conn.host == "garage.test"
      assert conn.request_path == "/rescord/org-1/attachments/abc"
      assert Plug.Conn.get_req_header(conn, "content-type") == ["image/png"]

      assert [authorization] = Plug.Conn.get_req_header(conn, "authorization")

      assert authorization =~
               ~r"^AWS4-HMAC-SHA256 Credential=GK0000000000000000000000ad/\d{8}/garage/s3/aws4_request"
    end

    test "puts the bucket in the host, with a signature for S3, when the address is virtual" do
      Shoddy.Tests.put_app_env(
        :rescord,
        S3,
        Keyword.merge(Application.get_env(:rescord, S3),
          endpoint: "https://t3.storage.dev",
          region: "auto",
          addressing: :virtual
        )
      )

      test = self()

      Req.Test.stub(S3, fn conn ->
        send(test, {:request, conn})
        Plug.Conn.send_resp(conn, 200, "bytes")
      end)

      assert S3.get("org-1/attachments/abc") == {:ok, "bytes"}
      assert_received {:request, conn}

      assert conn.scheme == :https
      assert conn.host == "rescord.t3.storage.dev"
      assert conn.request_path == "/org-1/attachments/abc"

      assert [authorization] = Plug.Conn.get_req_header(conn, "authorization")

      assert authorization =~
               ~r"^AWS4-HMAC-SHA256 Credential=GK0000000000000000000000ad/\d{8}/auto/s3/aws4_request"
    end

    test "gets a file, and says when there is none" do
      Req.Test.stub(S3, fn conn ->
        case conn.request_path do
          "/rescord/org-1/attachments/abc" -> Plug.Conn.send_resp(conn, 200, "bytes")
          _other -> Plug.Conn.send_resp(conn, 404, "")
        end
      end)

      assert S3.get("org-1/attachments/abc") == {:ok, "bytes"}
      assert S3.get("org-1/attachments/none") == {:error, :not_found}
    end

    test "deletes a file, and a file that is not there is no error" do
      Req.Test.stub(S3, fn conn ->
        if conn.method == "DELETE",
          do: Plug.Conn.send_resp(conn, if(conn.request_path =~ "none", do: 404, else: 204), ""),
          else: Plug.Conn.send_resp(conn, 405, "")
      end)

      assert :ok = S3.delete("org-1/attachments/abc")
      assert :ok = S3.delete("org-1/attachments/none")
    end

    test "returns an error for a refusal of the service" do
      Req.Test.stub(S3, fn conn -> Plug.Conn.send_resp(conn, 403, "") end)

      assert S3.put("org-1/attachments/abc", "bytes", "image/png") == {:error, {:status, 403}}
      assert S3.get("org-1/attachments/abc") == {:error, {:status, 403}}
      assert S3.list() == {:error, {:status, 403}}
    end

    defp listing(keys, more) do
      contents =
        Enum.map_join(keys, &"<Contents><Key>#{&1}</Key><Size>5</Size></Contents>")

      ~s(<?xml version="1.0" encoding="UTF-8"?>\n) <>
        ~s(<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">) <>
        "<Name>rescord</Name><Prefix></Prefix>#{contents}#{more}</ListBucketResult>"
    end

    defp send_listing(conn, keys, more) do
      conn
      |> Plug.Conn.put_resp_content_type("application/xml")
      |> Plug.Conn.send_resp(200, listing(keys, more))
    end

    test "lists the keys of each page of the bucket, with a signature for each request" do
      test = self()
      # A token with characters that a query and a signature must encode.
      token = "1/a+b= c&d"

      Req.Test.stub(S3, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        send(test, {:request, conn})

        case conn.query_params do
          %{"list-type" => "2", "continuation-token" => ^token} ->
            send_listing(conn, ["org-2/photos/c"], "<IsTruncated>false</IsTruncated>")

          %{"list-type" => "2"} = params when map_size(params) == 1 ->
            send_listing(
              conn,
              ["org-1/attachments/a", "org-1/photos/b &amp; c"],
              "<IsTruncated>true</IsTruncated>" <>
                "<NextContinuationToken>1/a+b= c&amp;d</NextContinuationToken>"
            )
        end
      end)

      assert S3.list() == {:ok, ["org-1/attachments/a", "org-1/photos/b & c", "org-2/photos/c"]}

      assert_received {:request, first}
      assert first.method == "GET"
      assert first.host == "garage.test"
      assert first.request_path == "/rescord"
      assert first.query_string == "list-type=2"

      assert_received {:request, second}
      assert second.request_path == "/rescord"

      assert second.query_string ==
               "list-type=2&continuation-token=1%2Fa%2Bb%3D%20c%26d"

      for conn <- [first, second] do
        assert [authorization] = Plug.Conn.get_req_header(conn, "authorization")

        assert authorization =~
                 ~r"^AWS4-HMAC-SHA256 Credential=GK0000000000000000000000ad/\d{8}/garage/s3/aws4_request"
      end
    end

    test "lists a bucket whose name is in the host, at the root of that host" do
      Shoddy.Tests.put_app_env(
        :rescord,
        S3,
        Keyword.merge(Application.get_env(:rescord, S3),
          endpoint: "https://t3.storage.dev",
          region: "auto",
          addressing: :virtual
        )
      )

      test = self()

      Req.Test.stub(S3, fn conn ->
        send(test, {:request, conn})
        send_listing(conn, ["org-1/attachments/a"], "<IsTruncated>false</IsTruncated>")
      end)

      assert S3.list() == {:ok, ["org-1/attachments/a"]}
      assert_received {:request, conn}

      assert conn.scheme == :https
      assert conn.host == "rescord.t3.storage.dev"
      assert conn.request_path == "/"
      assert conn.query_string == "list-type=2"

      assert [authorization] = Plug.Conn.get_req_header(conn, "authorization")

      assert authorization =~
               ~r"^AWS4-HMAC-SHA256 Credential=GK0000000000000000000000ad/\d{8}/auto/s3/aws4_request"
    end

    test "lists an empty bucket" do
      Req.Test.stub(S3, &send_listing(&1, [], "<IsTruncated>false</IsTruncated>"))
      assert S3.list() == {:ok, []}
      assert S3.files() == {:ok, []}
    end

    test "lists each file with the size that the bucket gives, over each page" do
      Req.Test.stub(S3, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        body =
          case conn.query_params do
            %{"continuation-token" => "next"} ->
              sized_listing([{"org-2/photos/c", "0"}], "<IsTruncated>false</IsTruncated>")

            _first ->
              sized_listing(
                [{"org-1/attachments/a", "5"}, {"org-1/photos/b", " 20971520 "}],
                "<IsTruncated>true</IsTruncated><NextContinuationToken>next</NextContinuationToken>"
              )
          end

        conn
        |> Plug.Conn.put_resp_content_type("application/xml")
        |> Plug.Conn.send_resp(200, body)
      end)

      assert S3.files() ==
               {:ok,
                [
                  {"org-1/attachments/a", 5},
                  {"org-1/photos/b", 20_971_520},
                  {"org-2/photos/c", 0}
                ]}
    end

    test "refuses a list with no size for a file, which names its keys all the same" do
      for size <- ["", "<Size></Size>", "<Size>large</Size>", "<Size>-1</Size>"] do
        body =
          ~s(<?xml version="1.0"?><ListBucketResult><Contents><Key>org-1/photos/a</Key>) <>
            size <> "</Contents><IsTruncated>false</IsTruncated></ListBucketResult>"

        Req.Test.stub(S3, fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/xml")
          |> Plug.Conn.send_resp(200, body)
        end)

        assert S3.files() == {:error, :bad_listing}, body
        assert S3.list() == {:ok, ["org-1/photos/a"]}, body
      end
    end

    # A page of a list as a service writes it, with the size of each file
    # after other facts of it.
    defp sized_listing(files, more) do
      contents =
        Enum.map_join(files, fn {key, size} ->
          "<Contents><Key>#{key}</Key><LastModified>2026-11-27T00:00:00.000Z</LastModified>" <>
            "<ETag>&quot;etag&quot;</ETag><Size>#{size}</Size>" <>
            "<Owner><ID>owner</ID><DisplayName>Size</DisplayName></Owner></Contents>"
        end)

      ~s(<?xml version="1.0" encoding="UTF-8"?>\n) <>
        ~s(<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">) <>
        "<Name>rescord</Name><KeyCount>#{length(files)}</KeyCount>#{contents}#{more}</ListBucketResult>"
    end

    test "refuses a list that it cannot read, and a list with more pages and no token" do
      for body <- [
            "not XML",
            ~s(<?xml version="1.0"?><Error><Code>Fault</Code></Error>),
            listing(["org-1/attachments/a"], "<IsTruncated>true</IsTruncated>"),
            # An entity, which the parser does not read.
            ~s(<?xml version="1.0"?><!DOCTYPE l [<!ENTITY e "x">]>) <>
              "<ListBucketResult><Contents><Key>&e;</Key></Contents></ListBucketResult>"
          ] do
        Req.Test.stub(S3, fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/xml")
          |> Plug.Conn.send_resp(200, body)
        end)

        assert S3.list() == {:error, :bad_listing}, body
        assert S3.files() == {:error, :bad_listing}, body
      end
    end
  end
end
