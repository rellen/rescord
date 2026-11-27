defmodule Rescord.FakeS3 do
  @moduledoc """
  A service that is compatible with S3, in the memory of a test (ADR 0059).
  `Rescord.Storage.S3` talks to it through the `:plug` of Req, so the test
  runs each request that the store builds and signs, and needs no service.
  `Rescord.StorageFixtures.s3_store!/1` starts one and names it in the
  settings of the store.

  It takes the bucket in the path, and does what Rescord asks of S3: put,
  get and delete an object, and ListObjectsV2 in pages, each with a token
  for the next one. It refuses a request with no signature, and does not
  check the signature: `Rescord.StorageTest` reads it.

  A test can make it fail (`fault/3`), and count the requests that it got
  (`requests/2`).
  """

  use Agent

  import Plug.Conn

  @doc """
  Starts the service.

  ## Options

    * `:bucket` - the one bucket, `"rescord"` at first;
    * `:page` - the keys in a page of a list, 2 at first, so that a test
      with a few files reads more than one page.
  """
  def start_link(opts \\ []) do
    state = %{
      bucket: Keyword.get(opts, :bucket, "rescord"),
      page: Keyword.get(opts, :page, 2),
      objects: %{},
      faults: %{},
      requests: []
    }

    Agent.start_link(fn -> state end)
  end

  @doc "The objects of the bucket: a map of each key to its bytes and its type."
  def objects(service), do: Agent.get(service, & &1.objects)

  @doc "Puts an object in the bucket, as a request did not."
  def put_object(service, key, bytes, type \\ "application/octet-stream"),
    do: Agent.update(service, &put_in(&1.objects[key], {bytes, type}))

  @doc """
  Makes the service fail until `clear_faults/1`. `target` is a key, or
  `:list` for the list of the bucket. `fault` is:

    * `{:put, status}` or `{:get, status}` - the answer to that request;
    * `:corrupt` - a put keeps other bytes than the ones that it got;
    * a status - the answer to a list.
  """
  def fault(service, target, fault), do: Agent.update(service, &put_in(&1.faults[target], fault))

  @doc "Takes each fault away."
  def clear_faults(service), do: Agent.update(service, &%{&1 | faults: %{}})

  @doc "The requests of the method `method` that the service got, oldest first, as paths."
  def requests(service, method) do
    Agent.get(service, fn state ->
      for {^method, path} <- Enum.reverse(state.requests), do: path
    end)
  end

  @doc "Answers a request, as the `:plug` of Req."
  def call(conn, service) do
    Agent.update(service, &%{&1 | requests: [{conn.method, conn.request_path} | &1.requests]})
    state = Agent.get(service, & &1)

    case {get_req_header(conn, "authorization"), conn.path_info} do
      {["AWS4-HMAC-SHA256 " <> _signature], [bucket | segments]} when bucket == state.bucket ->
        object(conn, service, state, Enum.join(segments, "/"))

      {[_signed], _other_bucket} ->
        send_resp(conn, 404, error("NoSuchBucket"))

      {_no_signature, _path} ->
        send_resp(conn, 403, error("AccessDenied"))
    end
  end

  # The bucket itself: the list.
  defp object(%{method: "GET"} = conn, _service, state, "") do
    conn = fetch_query_params(conn)

    case {conn.query_params, state.faults[:list]} do
      {%{"list-type" => "2"} = params, nil} ->
        conn
        |> put_resp_content_type("application/xml")
        |> send_resp(200, list(state, params["continuation-token"]))

      {%{"list-type" => "2"}, status} ->
        send_resp(conn, status, error("Fault"))

      _other ->
        send_resp(conn, 400, error("InvalidRequest"))
    end
  end

  defp object(%{method: "PUT"} = conn, service, state, key) do
    {:ok, bytes, conn} = read_body(conn, length: 50_000_000)
    [type] = get_req_header(conn, "content-type")

    case state.faults[key] do
      {:put, status} ->
        send_resp(conn, status, error("Fault"))

      :corrupt ->
        put_object(service, key, bytes <> "!", type)
        send_resp(conn, 200, "")

      _none ->
        put_object(service, key, bytes, type)
        send_resp(conn, 200, "")
    end
  end

  defp object(%{method: "GET"} = conn, _service, state, key) do
    case {state.faults[key], state.objects[key]} do
      {{:get, status}, _object} ->
        send_resp(conn, status, error("Fault"))

      {_none, {bytes, type}} ->
        conn |> put_resp_content_type(type, nil) |> send_resp(200, bytes)

      {_none, nil} ->
        send_resp(conn, 404, error("NoSuchKey"))
    end
  end

  defp object(%{method: "DELETE"} = conn, service, _state, key) do
    Agent.update(service, &%{&1 | objects: Map.delete(&1.objects, key)})
    send_resp(conn, 204, "")
  end

  defp object(conn, _service, _state, _key), do: send_resp(conn, 405, error("MethodNotAllowed"))

  # A page of the keys in order. The token of the next page is the last
  # key of this one, with characters that a query must encode.
  defp list(state, token) do
    keys = state.objects |> Map.keys() |> Enum.sort()

    after_key =
      case token do
        nil -> nil
        "after " <> encoded -> Base.decode64!(encoded)
      end

    rest = if after_key, do: Enum.drop_while(keys, &(&1 <= after_key)), else: keys
    {page, more} = Enum.split(rest, state.page)

    contents =
      Enum.map_join(page, fn key ->
        {bytes, _type} = state.objects[key]

        "<Contents><Key>#{escape(key)}</Key><LastModified>2026-11-27T00:00:00.000Z</LastModified>" <>
          "<ETag>&quot;etag&quot;</ETag><Size>#{byte_size(bytes)}</Size>" <>
          "<StorageClass>STANDARD</StorageClass></Contents>"
      end)

    next =
      if more == [],
        do: "",
        else:
          "<NextContinuationToken>after #{Base.encode64(List.last(page))}</NextContinuationToken>"

    ~s(<?xml version="1.0" encoding="UTF-8"?>\n) <>
      ~s(<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">) <>
      "<Name>#{state.bucket}</Name><Prefix></Prefix><KeyCount>#{length(page)}</KeyCount>" <>
      "<MaxKeys>#{state.page}</MaxKeys><IsTruncated>#{more != []}</IsTruncated>" <>
      contents <> next <> "</ListBucketResult>"
  end

  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp error(code),
    do: ~s(<?xml version="1.0" encoding="UTF-8"?>\n<Error><Code>#{code}</Code></Error>)
end
