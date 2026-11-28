defmodule Rescord.Storage.Scan.Clamd do
  @moduledoc """
  Speaks to clamd, the daemon of ClamAV, over a socket (issue 37,
  ADR 0113). No library: the commands are a few lines with `:gen_tcp`.

  An address is `host:port` for TCP, such as `clamd:3310` or
  `[::1]:3310`, or the absolute path of a Unix socket, such as
  `/run/clamav/clamd.ctl` (`parse/1`).

  Each command starts with `z` and ends with a zero byte, and so does its
  answer (the "z" form of the commands of clamd):

    * `zPING` answers `PONG`;
    * `zINSTREAM` sends the bytes in chunks, each one after its length in
      4 bytes (big-endian), and a chunk of length 0 at the end. The answer
      is `stream: OK`, `stream: <name> FOUND`, or a line that ends with
      `ERROR`, such as `INSTREAM size limit exceeded. ERROR` for a file
      larger than the `StreamMaxLength` of clamd.

  The connection takes at most 5 seconds, and the answer at most
  `timeout/0`, 30 seconds, unless a call gives another time.
  """

  @connect_timeout 5_000
  @timeout 30_000
  @chunk 262_144

  @typedoc "Where clamd listens: a host and a port, or the path of a Unix socket."
  @type target :: {:tcp, charlist | :inet.ip_address(), :inet.port_number()} | {:unix, String.t()}

  @typedoc "What a scan found: nothing, a signature by its name, or a fault."
  @type result :: :clean | {:found, String.t()} | {:fault, String.t()}

  @doc "The longest wait for an answer, in milliseconds."
  @spec timeout() :: pos_integer
  def timeout, do: @timeout

  @doc """
  The target of an address, or `:error` for an address that is neither
  `host:port` nor an absolute path.

      iex> Rescord.Storage.Scan.Clamd.parse("clamd:3310")
      {:ok, {:tcp, ~c"clamd", 3310}}

      iex> Rescord.Storage.Scan.Clamd.parse("[::1]:3310")
      {:ok, {:tcp, {0, 0, 0, 0, 0, 0, 0, 1}, 3310}}

      iex> Rescord.Storage.Scan.Clamd.parse("/run/clamav/clamd.ctl")
      {:ok, {:unix, "/run/clamav/clamd.ctl"}}

      iex> Rescord.Storage.Scan.Clamd.parse("clamd")
      :error
  """
  @spec parse(String.t()) :: {:ok, target} | :error
  def parse("/" <> _rest = path) do
    if String.match?(path, ~r/^\/[^\s\x00]+$/), do: {:ok, {:unix, path}}, else: :error
  end

  def parse("[" <> rest) do
    with [ip, ":" <> port] <- String.split(rest, "]", parts: 2),
         {:ok, address} <- :inet.parse_ipv6strict_address(String.to_charlist(ip)),
         {:ok, port} <- port(port) do
      {:ok, {:tcp, address, port}}
    else
      _no -> :error
    end
  end

  def parse(address) when is_binary(address) do
    with [host, port] <- String.split(address, ":"),
         true <- String.match?(host, ~r/^[A-Za-z0-9_]([A-Za-z0-9._-]{0,252}[A-Za-z0-9_])?$/),
         {:ok, port} <- port(port) do
      {:ok, {:tcp, String.to_charlist(host), port}}
    else
      _no -> :error
    end
  end

  def parse(_address), do: :error

  defp port(text) do
    case Integer.parse(text) do
      {port, ""} when port in 1..65_535 -> {:ok, port}
      _no -> :error
    end
  end

  @doc "Sends `zPING`: `:ok` when clamd answers `PONG`."
  @spec ping(target, pos_integer) :: :ok | {:fault, String.t()}
  def ping(target, timeout \\ @timeout) do
    with {:ok, socket} <- connect(target) do
      try do
        with :ok <- put(socket, "zPING\0"),
             {:ok, "PONG"} <- answer(socket, timeout) do
          :ok
        else
          {:ok, other} -> {:fault, "answered #{printable(other)}"}
          {:fault, _words} = fault -> fault
        end
      after
        :gen_tcp.close(socket)
      end
    end
  end

  @doc "Sends `bytes` with `zINSTREAM`, and says what clamd found."
  @spec scan(target, binary, pos_integer) :: result
  def scan(target, bytes, timeout \\ @timeout) when is_binary(bytes) do
    with {:ok, socket} <- connect(target) do
      try do
        with :ok <- put(socket, "zINSTREAM\0"),
             :ok <- send_chunks(socket, bytes),
             {:ok, answer} <- answer(socket, timeout) do
          read(answer)
        end
      after
        :gen_tcp.close(socket)
      end
    end
  end

  @doc """
  What an answer to `zINSTREAM` means.

      iex> Rescord.Storage.Scan.Clamd.read("stream: OK")
      :clean

      iex> Rescord.Storage.Scan.Clamd.read("stream: Eicar-Test-Signature FOUND")
      {:found, "Eicar-Test-Signature"}

      iex> Rescord.Storage.Scan.Clamd.read("INSTREAM size limit exceeded. ERROR")
      {:fault, "answered INSTREAM size limit exceeded. ERROR"}
  """
  @spec read(String.t()) :: result
  def read("stream: OK"), do: :clean

  def read("stream: " <> rest = answer) do
    case String.split(rest, " FOUND", parts: 2) do
      [name, ""] when name != "" -> {:found, printable(name)}
      _other -> {:fault, "answered #{printable(answer)}"}
    end
  end

  def read(answer), do: {:fault, "answered #{printable(answer)}"}

  defp connect({:tcp, host, port}), do: open(host, port)
  defp connect({:unix, path}), do: open({:local, String.to_charlist(path)}, 0)

  defp open(host, port) do
    case :gen_tcp.connect(host, port, [:binary, active: false, packet: :raw], @connect_timeout) do
      {:ok, socket} -> {:ok, socket}
      {:error, reason} -> {:fault, "cannot be reached: #{reason(reason)}"}
    end
  end

  defp put(socket, bytes) do
    case :gen_tcp.send(socket, bytes) do
      :ok -> :ok
      {:error, reason} -> {:fault, "closed the connection: #{reason(reason)}"}
    end
  end

  defp send_chunks(socket, <<chunk::binary-size(@chunk), rest::binary>>) do
    with :ok <- put(socket, [<<@chunk::32-big>>, chunk]), do: send_chunks(socket, rest)
  end

  # A chunk of length 0 ends the stream, so an empty rest sends that alone.
  defp send_chunks(socket, ""), do: put(socket, <<0::32-big>>)

  defp send_chunks(socket, rest),
    do: put(socket, [<<byte_size(rest)::32-big>>, rest, <<0::32-big>>])

  # The answer ends with a zero byte. clamd closes the connection after it.
  defp answer(socket, timeout, read \\ "") do
    case :gen_tcp.recv(socket, 0, timeout) do
      {:ok, bytes} ->
        all = read <> bytes

        case :binary.split(all, "\0") do
          [answer, _rest] -> {:ok, answer}
          [_partial] when byte_size(all) < 4_096 -> answer(socket, timeout, all)
          [_partial] -> {:fault, "sent an answer with no end"}
        end

      {:error, :closed} when read != "" ->
        {:ok, read}

      {:error, :timeout} ->
        {:fault, "did not answer in #{seconds(timeout)}"}

      {:error, reason} ->
        {:fault, "closed the connection: #{reason(reason)}"}
    end
  end

  defp seconds(timeout) when timeout >= 1_000, do: "#{div(timeout, 1_000)} seconds"
  defp seconds(timeout), do: "#{timeout} milliseconds"

  defp reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason(_reason), do: "an error of the socket"

  # The words of clamd go into the log and onto a page: printable
  # characters only, and not too many.
  defp printable(text) do
    text
    |> String.replace(~r/[^\x20-\x7E]/, "?")
    |> String.slice(0, 200)
  end
end
