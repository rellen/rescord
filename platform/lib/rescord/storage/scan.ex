defmodule Rescord.Storage.Scan do
  @moduledoc """
  The virus scan of the PDFs that people send (issue 37, ADR 0113).

  A root user turns it on at `/root/scan`, with the address of clamd
  (`Rescord.Storage.Scan.Settings`). Then `check/1` sends each PDF to
  clamd (`Rescord.Storage.Scan.Clamd`) before a journal file or a receipt
  is written:

    * a file that clamd finds harmful is refused with the reason
      `:infected` of `Rescord.Storage.Errors.RefusedFile`, and the log has a
      warning with the name that clamd gave, and no name of the file;
    * with no answer of clamd, the file is refused with the reason
      `:unscanned`: a root user who turned the scan on wants no PDF that was
      not scanned.

  A photo is not scanned: Rescord writes it again from its pixels
  (ADR 0055), so the bytes that were sent are not what it keeps. With no
  row, or with the scan off, `check/1` lets each file through, as before.

  Each scan emits `[:rescord, :scan, :stop]` with the result (`:clean`,
  `:found` or `:fault`), which the metrics count.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  require Logger

  alias Rescord.Storage.Errors.RefusedFile
  alias Rescord.Storage.Scan.{Clamd, Settings}

  boundary do
    # A relationship and a signal listener are checked too (ADR 0066).
    check aliases: true
    deps [Rescord, Rescord.Accounts]
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Settings do
      define :read_settings, action: :read
      define :set_settings, action: :set
      define :change_settings, action: :change
    end
  end

  @doc """
  The settings of the scan: the row of the server, read with no actor, or
  the start values (off, no address) when it has none.
  """
  @spec settings() :: Settings.t()
  def settings do
    case read_settings(authorize?: false) do
      {:ok, [settings | _]} -> settings
      _none -> %Settings{scan_on: false, address: nil}
    end
  end

  @doc "Whether the scan is on, with an address."
  @spec on?() :: boolean
  def on? do
    match?(%Settings{scan_on: true, address: address} when is_binary(address), settings())
  end

  @doc "Saves the settings of the scan, as the root user of `options`."
  @spec save_settings(map, keyword) :: {:ok, Settings.t()} | {:error, term}
  def save_settings(params, options) do
    case read_settings(options) do
      {:ok, [settings | _]} -> change_settings(settings, params, options)
      {:ok, []} -> set_settings(params, options)
      error -> error
    end
  end

  @doc """
  Sends `zPING` to clamd at `address`: `:ok` when it answers, or
  `{:fault, words}`, which say what went wrong and name no file.
  """
  @spec ping(String.t() | nil) :: :ok | {:fault, String.t()}
  def ping(address) when is_binary(address) do
    case Clamd.parse(address) do
      {:ok, target} -> Clamd.ping(target)
      :error -> {:fault, "is not host:port or the path of a socket"}
    end
  end

  def ping(_address), do: {:fault, "is not set"}

  @doc """
  Lets a prepared file through (`Rescord.Storage.Upload.prepare/1`), or
  refuses it. Only a PDF goes to clamd, and only when the scan is on.
  """
  @spec check(%{required(:content_type) => String.t(), required(:bytes) => binary}) ::
          :ok | {:error, RefusedFile.t()}
  def check(%{content_type: "application/pdf", bytes: bytes}) do
    case settings() do
      %Settings{scan_on: true, address: address} when is_binary(address) -> scan(address, bytes)
      _off -> :ok
    end
  end

  def check(%{}), do: :ok

  defp scan(address, bytes) do
    result =
      case Clamd.parse(address) do
        {:ok, target} -> Clamd.scan(target, bytes)
        :error -> {:fault, "has an address that is not host:port or the path of a socket"}
      end

    :telemetry.execute([:rescord, :scan, :stop], %{count: 1}, %{result: kind(result)})

    case result do
      :clean ->
        :ok

      {:found, name} ->
        Logger.warning("The virus scan found #{name} in a PDF, and Rescord refused the file.")
        {:error, RefusedFile.exception(reason: :infected)}

      {:fault, words} ->
        Logger.warning("clamd #{words}, so Rescord refused a PDF that it could not scan.")
        {:error, RefusedFile.exception(reason: :unscanned)}
    end
  end

  defp kind(:clean), do: :clean
  defp kind({:found, _name}), do: :found
  defp kind({:fault, _words}), do: :fault
end
