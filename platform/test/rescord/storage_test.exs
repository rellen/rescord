defmodule Rescord.StorageTest do
  @moduledoc """
  Holds the stores of files (ADR 0038): the key of a file, the store in a
  directory that the tests use, and the requests that the store of S3
  signs, which a stub of `Req.Test` reads in place of a service.

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
  end

  describe "the store in a directory" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      previous = Application.get_env(:rescord, Disk)
      Application.put_env(:rescord, Disk, root: tmp_dir)
      on_exit(fn -> Application.put_env(:rescord, Disk, previous) end)
      :ok
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
  end

  describe "the store of S3" do
    setup do
      previous = Application.get_env(:rescord, S3)

      Application.put_env(:rescord, S3,
        endpoint: "http://garage.test:3900",
        region: "garage",
        bucket: "rescord",
        access_key_id: "GK0000000000000000000000ad",
        secret_access_key: "000000000000000000000000000000000000000000000000000000000000dec0",
        req_options: [plug: {Req.Test, S3}, retry: false]
      )

      on_exit(fn ->
        if previous,
          do: Application.put_env(:rescord, S3, previous),
          else: Application.delete_env(:rescord, S3)
      end)

      :ok
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
    end
  end
end
