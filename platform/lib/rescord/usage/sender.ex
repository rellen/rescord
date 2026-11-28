defmodule Rescord.Usage.Sender do
  @moduledoc """
  Sends one document to the address of the settings (ADR 0098), with
  `POST` and `Req`, and says what the address answered: `{:ok, status}`
  for an answer with a status 2xx, `{:status, status}` for any other one,
  `:unreachable` when no answer came, and `:sealed` when this server
  cannot open the token.

  It follows no redirect and tries one time: the next hour tries again.
  The headers are `content-type: application/json`, `user-agent:
  rescord/<version>`, and `authorization: Bearer <token>` when a root user
  set a token. This is the one module that decrypts the token.

  `config :rescord, Rescord.Usage.Sender, req_options: [...]` adds options
  of `Req`, so that a test gives `plug: {Req.Test, Rescord.Usage.Sender}`.
  """

  alias Rescord.Usage.Settings

  @type result :: {:ok, 200..299} | {:status, integer} | :unreachable | :sealed

  @doc "Sends `body` to the address of `settings`."
  @spec post(Settings.t(), String.t()) :: result
  def post(%Settings{endpoint: endpoint} = settings, body) when is_binary(endpoint) do
    with {:ok, headers} <- headers(settings) do
      options =
        [
          url: endpoint,
          body: body,
          headers: headers,
          redirect: false,
          retry: false,
          connect_options: [timeout: 10_000],
          receive_timeout: 20_000
        ]
        |> Keyword.merge(Keyword.get(config(), :req_options, []))

      case Req.post(options) do
        {:ok, %Req.Response{status: status}} when status in 200..299 -> {:ok, status}
        {:ok, %Req.Response{status: status}} -> {:status, status}
        {:error, _exception} -> :unreachable
      end
    end
  end

  defp headers(settings) do
    base = [
      {"content-type", "application/json"},
      {"user-agent", "rescord/#{Rescord.version()}"}
    ]

    case token(settings) do
      {:ok, nil} -> {:ok, base}
      {:ok, token} -> {:ok, [{"authorization", "Bearer " <> token} | base]}
      :sealed -> :sealed
    end
  end

  defp token(%Settings{token_set_at: nil}), do: {:ok, nil}

  defp token(settings) do
    case Ash.load(settings, :token, authorize?: false, context: %{rescord_vault: :open}) do
      {:ok, %{token: token}} when is_binary(token) or is_nil(token) -> {:ok, token}
      _other -> :sealed
    end
  rescue
    # A value that cannot be opened raises out of `Ash.load/3`, and not
    # always the same error (see `Rescord.Ruby.LLM`).
    _error -> :sealed
  end

  defp config, do: Application.get_env(:rescord, __MODULE__, [])
end
