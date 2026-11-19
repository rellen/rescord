defmodule Rescord.Storage.S3 do
  @moduledoc """
  A store of files in a bucket of a service that is compatible with S3
  (ADR 0038): Tigris in production, and Garage on a machine for
  development. `req_s3`, a plugin of `Req`, signs each request.

  The configuration comes from the environment at run time
  (`config/runtime.exs`), and never from a file in the repository:

      config :rescord, Rescord.Storage.S3,
        endpoint: "https://t3.storage.dev",
        region: "auto",
        bucket: "rescord",
        access_key_id: "...",
        secret_access_key: "..."

  For an endpoint that is not on `s3.amazonaws.com`, `req_s3` puts the
  bucket in the path of the URL, which Garage and Tigris both take. The
  module gives the keys to `req_s3` itself, so `req_s3` never reads the
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

  defp url(key), do: "s3://#{Keyword.fetch!(config(), :bucket)}/#{key}"

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
        region: Keyword.fetch!(config, :region)
      ]
    )
  end
end
