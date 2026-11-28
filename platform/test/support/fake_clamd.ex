defmodule Rescord.FakeClamd do
  @moduledoc """
  A clamd for the tests of the virus scan (issue 37): a `:gen_tcp` server
  on a free port of 127.0.0.1, or on a Unix socket, that speaks the "z"
  form of `PING` and `INSTREAM`.

  `start/1` takes what the fake does with a scan:

    * `:clean` answers `stream: OK`;
    * `{:found, name}` answers `stream: <name> FOUND`;
    * `{:answer, words}` answers `words`;
    * `:silent` reads the file and never answers.

  Each file that the fake receives goes to the test process as
  `{:clamd_scanned, bytes}`. The server stops with the test.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  @doc """
  Starts the fake, and returns its address as a setting holds it: `host:port`,
  or the path of the socket with `socket: path`.
  """
  def start(mode, opts \\ []) do
    test = self()

    {listen, address} =
      case Keyword.get(opts, :socket) do
        nil ->
          {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
          {:ok, port} = :inet.port(listen)
          {listen, "127.0.0.1:#{port}"}

        path ->
          File.rm(path)

          {:ok, listen} =
            :gen_tcp.listen(0, [
              :binary,
              active: false,
              ifaddr: {:local, String.to_charlist(path)}
            ])

          {listen, path}
      end

    server = spawn(fn -> accept(listen, mode, test) end)
    :ok = :gen_tcp.controlling_process(listen, server)

    on_exit(fn ->
      Process.exit(server, :kill)
      if Keyword.has_key?(opts, :socket), do: File.rm(Keyword.fetch!(opts, :socket))
    end)

    address
  end

  @doc "An address where nothing listens: a port that was free a moment ago."
  def nobody do
    {:ok, listen} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(listen)
    :ok = :gen_tcp.close(listen)
    "127.0.0.1:#{port}"
  end

  defp accept(listen, mode, test) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} ->
        serve(socket, mode, test)
        accept(listen, mode, test)

      {:error, _reason} ->
        :ok
    end
  end

  defp serve(socket, mode, test) do
    case command(socket, "") do
      {"zPING", _rest} ->
        :gen_tcp.send(socket, "PONG\0")

      {"zINSTREAM", rest} ->
        bytes = chunks(socket, rest, [])
        send(test, {:clamd_scanned, bytes})
        reply(socket, mode)

      _other ->
        :ok
    end

    :gen_tcp.close(socket)
  end

  defp reply(_socket, :silent), do: Process.sleep(:infinity)
  defp reply(socket, :clean), do: :gen_tcp.send(socket, "stream: OK\0")
  defp reply(socket, {:found, name}), do: :gen_tcp.send(socket, "stream: #{name} FOUND\0")
  defp reply(socket, {:answer, words}), do: :gen_tcp.send(socket, words <> "\0")

  defp command(socket, read) do
    case :binary.split(read, "\0") do
      [command, rest] ->
        {command, rest}

      [_partial] ->
        {:ok, bytes} = :gen_tcp.recv(socket, 0, 5_000)
        command(socket, read <> bytes)
    end
  end

  defp chunks(_socket, <<0::32-big, _rest::binary>>, read),
    do: read |> Enum.reverse() |> IO.iodata_to_binary()

  defp chunks(socket, <<size::32-big, chunk::binary-size(size), rest::binary>>, read),
    do: chunks(socket, rest, [chunk | read])

  defp chunks(socket, partial, read) do
    {:ok, bytes} = :gen_tcp.recv(socket, 0, 5_000)
    chunks(socket, partial <> bytes, read)
  end
end
