defmodule Rescord.Storage.S3 do
  @moduledoc """
  A store of files in a bucket of a service that is compatible with S3
  (ADR 0038, ADR 0045): Garage on a machine for development, and the service
  that the operator of a server names. `req_s3` and `Req` sign each request
  with AWS Signature Version 4.

  The configuration comes from the environment at run time
  (`config/runtime.exs`), and never from a file in the repository:

      config :rescord, Rescord.Storage.S3,
        endpoint: "https://t3.storage.dev",
        region: "auto",
        bucket: "rescord",
        addressing: :virtual,
        access_key_id: "...",
        secret_access_key: "..."

  `:addressing` says where the name of the bucket goes:

    * `:path`, the default, puts it in the path, as in
      `https://s3.example.org/rescord/KEY`. Garage and MinIO take it as
      they are set up by default.
    * `:virtual` puts it in the host, as in
      `https://rescord.t3.storage.dev/KEY`. Tigris takes nothing else for a
      bucket made after 19 February 2025.

  The module gives the keys to `req_s3` itself, so `req_s3` never reads the
  `AWS_` variables of the environment.

  `:req_options`, in the configuration of a test alone, goes to `Req.new/1`:
  a test gives `plug: {Req.Test, Rescord.Storage.S3}` and reads the request
  that this module signs.
  """

  @behaviour Rescord.Storage

  @impl true
  def put(key, bytes, content_type) when is_binary(bytes) do
    case Req.put(request(), url: url(key), body: bytes, headers: [content_type: content_type]) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status}} -> {:error, {:status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get(key) do
    case Req.get(request(), url: url(key), decode_body: false) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status}} -> {:error, {:status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete(key) do
    case Req.delete(request(), url: url(key)) do
      {:ok, %{status: status}} when status in 200..299 or status == 404 -> :ok
      {:ok, %{status: status}} -> {:error, {:status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists the key of each file in the bucket, with ListObjectsV2: a page of
  1000 keys at most for each request, until the service says that no page
  is left.
  """
  @impl true
  def list do
    with {:ok, files} <- pages(nil, []), do: {:ok, Enum.map(files, &elem(&1, 0))}
  end

  @doc """
  Lists each file as `list/0` does, with its size in bytes: ListObjectsV2
  gives the size of each object beside its key, so no request reads a
  file. A list that gives no size for an object is `{:error, :bad_listing}`.
  """
  @impl true
  def files do
    with {:ok, files} <- pages(nil, []) do
      if Enum.all?(files, fn {_key, size} -> is_integer(size) end),
        do: {:ok, files},
        else: {:error, :bad_listing}
    end
  end

  # Each page of the list, as `{key, size}`. The size is `nil` for an
  # object whose size the service did not give as a number.
  defp pages(token, found) do
    with {:ok, %{status: 200, body: body}} <-
           Req.get(request(), url: list_url(token), decode_body: false),
         {:ok, page} <- parse_page(body) do
      found = [page.files | found]

      case page do
        %{truncated?: false} -> {:ok, found |> Enum.reverse() |> Enum.concat()}
        %{token: token} when is_binary(token) -> pages(token, found)
        # More pages, and no way to ask for the next one.
        _no_token -> {:error, :bad_listing}
      end
    else
      {:ok, %{status: status}} -> {:error, {:status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # The address of the bucket itself, with the query of ListObjectsV2. The
  # query is in the address, and not in `:params` of Req: Req signs the
  # query as it is written, and a signature needs `%20` for a space, where
  # `:params` writes `+`.
  defp list_url(token) do
    config = config()
    bucket = Keyword.fetch!(config, :bucket)

    query =
      [{"list-type", "2"}] ++ if(token, do: [{"continuation-token", token}], else: [])

    query =
      Enum.map_join(query, "&", fn {name, value} ->
        name <> "=" <> URI.encode(value, &URI.char_unreserved?/1)
      end)

    case Keyword.get(config, :addressing, :path) do
      :path ->
        "s3://#{bucket}?#{query}"

      :virtual ->
        endpoint = URI.parse(Keyword.fetch!(config, :endpoint))
        path = String.trim_trailing(endpoint.path || "", "/") <> "/"
        URI.to_string(%{endpoint | host: "#{bucket}.#{endpoint.host}", path: path, query: query})
    end
  end

  # Reads a page of ListObjectsV2: the key and the size of each object,
  # whether more pages follow, and the token that asks for the next page.
  # The parser of Erlang reads no entity of the document and nothing from
  # outside it.
  defp parse_page(xml) do
    page = %{
      listing?: false,
      path: [],
      text: "",
      files: [],
      key: nil,
      size: nil,
      truncated?: false,
      token: nil
    }

    options = [
      :disallow_entities,
      event_fun: &page_event/3,
      event_state: page,
      external_entities: :none,
      fail_undeclared_ref: false
    ]

    case :xmerl_sax_parser.stream(xml, options) do
      {:ok, %{listing?: true, files: files} = page, _rest} ->
        {:ok, %{page | files: Enum.reverse(files)}}

      # A document that is no XML, or the XML of something else.
      _fault ->
        {:error, :bad_listing}
    end
  end

  defp page_event({:startElement, _uri, ~c"ListBucketResult", _qualified, _attributes}, _, page)
       when page.path == [],
       do: %{page | listing?: true, path: [~c"ListBucketResult"], text: ""}

  defp page_event({:startElement, _uri, name, _qualified, _attributes}, _location, page),
    do: %{page | path: [name | page.path], text: ""}

  # The parser can give the text of one element in several parts.
  defp page_event({:characters, text}, _location, page),
    do: %{page | text: page.text <> List.to_string(text)}

  defp page_event({:endElement, _uri, _name, _qualified}, _location, page) do
    [name | above] = page.path
    text = page.text
    page = %{page | path: above, text: ""}

    case {name, above} do
      {~c"Key", [~c"Contents", ~c"ListBucketResult"]} ->
        %{page | key: text}

      {~c"Size", [~c"Contents", ~c"ListBucketResult"]} ->
        %{page | size: size(text)}

      # The end of an object: its key and its size are read.
      {~c"Contents", [~c"ListBucketResult"]} when is_binary(page.key) ->
        %{page | files: [{page.key, page.size} | page.files], key: nil, size: nil}

      {~c"IsTruncated", [~c"ListBucketResult"]} ->
        %{page | truncated?: String.trim(text) == "true"}

      {~c"NextContinuationToken", [~c"ListBucketResult"]} ->
        %{page | token: text}

      _other ->
        page
    end
  end

  defp page_event(_event, _location, page), do: page

  defp size(text) do
    case Integer.parse(String.trim(text)) do
      {size, ""} when size >= 0 -> size
      _other -> nil
    end
  end

  defp config, do: Application.fetch_env!(:rescord, __MODULE__)

  defp url(key) do
    config = config()
    bucket = Keyword.fetch!(config, :bucket)

    case Keyword.get(config, :addressing, :path) do
      # `req_s3` turns this into the endpoint, the bucket and the key.
      :path ->
        "s3://#{bucket}/#{key}"

      :virtual ->
        endpoint = URI.parse(Keyword.fetch!(config, :endpoint))
        path = String.trim_trailing(endpoint.path || "", "/") <> "/" <> key
        URI.to_string(%{endpoint | host: "#{bucket}.#{endpoint.host}", path: path})
    end
  end

  defp request do
    config = config()

    [retry: :transient, max_retries: 2]
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Req.new()
    |> ReqS3.attach(
      aws_endpoint_url_s3: Keyword.fetch!(config, :endpoint),
      aws_sigv4: [
        access_key_id: Keyword.fetch!(config, :access_key_id),
        secret_access_key: Keyword.fetch!(config, :secret_access_key),
        region: Keyword.fetch!(config, :region),
        # Req cannot tell the service from the host of a service that is not
        # Amazon, and `req_s3` names it only for an `s3://` URL.
        service: :s3
      ]
    )
  end
end
