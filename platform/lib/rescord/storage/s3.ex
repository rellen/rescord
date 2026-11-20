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
