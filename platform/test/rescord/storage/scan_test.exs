defmodule Rescord.Storage.ScanTest do
  @moduledoc """
  Holds the virus scan of the PDFs (issue 37, ADR 0113) against a fake
  clamd (`Rescord.FakeClamd`): what clamd answers, over TCP and over a Unix
  socket; that a PDF is refused when clamd finds something or does not
  answer, and that a photo never goes to clamd; that only a root user reads
  and changes the settings; and the line of `bin/check`.

  The EICAR test file only goes to a real clamd, by hand.
  """

  use Rescord.DataCase, async: false

  import ExUnit.CaptureLog
  import Rescord.AccountsFixtures
  import Rescord.StorageFixtures

  alias Rescord.FakeClamd
  alias Rescord.Release.Check
  alias Rescord.Storage.Errors.RefusedFile
  alias Rescord.Storage.Scan
  alias Rescord.Storage.Scan.Clamd

  doctest Clamd

  defp target(address) do
    {:ok, target} = Clamd.parse(address)
    target
  end

  defp turn_on!(address) do
    {:ok, _settings} = Scan.save_settings(%{scan_on: true, address: address}, actor: root!())
    :ok
  end

  describe "clamd" do
    test "answers a PING, and says what it found in a file, over TCP" do
      assert Clamd.ping(target(FakeClamd.start(:clean))) == :ok

      # More than one chunk, and the end of the stream.
      bytes = :crypto.strong_rand_bytes(600_000)
      assert Clamd.scan(target(FakeClamd.start(:clean)), bytes) == :clean
      assert_received {:clamd_scanned, ^bytes}

      address = FakeClamd.start({:found, "Eicar-Test-Signature"})
      assert Clamd.scan(target(address), pdf()) == {:found, "Eicar-Test-Signature"}

      address = FakeClamd.start({:answer, "INSTREAM size limit exceeded. ERROR"})

      assert Clamd.scan(target(address), pdf()) ==
               {:fault, "answered INSTREAM size limit exceeded. ERROR"}
    end

    test "speaks over a Unix socket too" do
      # The path of a socket has at most 107 bytes, less than a tmp_dir of
      # ExUnit can have.
      path = Path.join(System.tmp_dir!(), "clamd-#{System.unique_integer([:positive])}.ctl")
      address = FakeClamd.start(:clean, socket: path)
      assert Clamd.ping(target(address)) == :ok
      assert Clamd.scan(target(address), "") == :clean
      assert_received {:clamd_scanned, ""}
    end

    test "is a fault when nobody listens, and when it does not answer in time" do
      assert {:fault, "cannot be reached: econnrefused"} =
               Clamd.scan(target(FakeClamd.nobody()), pdf())

      assert Clamd.scan(target(FakeClamd.start(:silent)), pdf(), 200) ==
               {:fault, "did not answer in 200 milliseconds"}
    end
  end

  describe "check/1" do
    test "lets each file through while the scan is off, and sends none to clamd" do
      FakeClamd.start({:found, "Never"})
      assert Scan.check(%{content_type: "application/pdf", bytes: pdf()}) == :ok
      refute_received {:clamd_scanned, _bytes}
    end

    test "refuses a PDF that clamd finds harmful, and logs the name of the find alone" do
      turn_on!(FakeClamd.start({:found, "Win.Test.EICAR_HDB-1"}))

      log =
        capture_log(fn ->
          assert {:error, %RefusedFile{reason: :infected} = error} =
                   Scan.check(%{content_type: "application/pdf", bytes: pdf()})

          assert Exception.message(error) =~ "the virus scan found harmful"
        end)

      assert log =~ "The virus scan found Win.Test.EICAR_HDB-1 in a PDF"
    end

    test "refuses a PDF while clamd does not answer" do
      turn_on!(FakeClamd.nobody())

      capture_log(fn ->
        assert {:error, %RefusedFile{reason: :unscanned} = error} =
                 Scan.check(%{content_type: "application/pdf", bytes: pdf()})

        assert Exception.message(error) =~ "could not be checked for viruses"
      end)
    end

    test "lets a clean PDF through, and never sends a photo" do
      turn_on!(FakeClamd.start(:clean))
      assert Scan.check(%{content_type: "application/pdf", bytes: pdf()}) == :ok
      assert_received {:clamd_scanned, _bytes}

      assert Scan.check(%{content_type: "image/jpeg", bytes: stored_jpeg()}) == :ok
      refute_received {:clamd_scanned, _bytes}
    end

    test "counts each scan by its result" do
      ref = :telemetry_test.attach_event_handlers(self(), [[:rescord, :scan, :stop]])
      turn_on!(FakeClamd.start(:clean))
      Scan.check(%{content_type: "application/pdf", bytes: pdf()})
      assert_received {[:rescord, :scan, :stop], ^ref, %{count: 1}, %{result: :clean}}
    end
  end

  describe "the settings" do
    test "only a root user reads and changes them" do
      user = user!()

      assert {:error, %Ash.Error.Forbidden{}} =
               Scan.save_settings(%{scan_on: false, address: "clamd:3310"}, actor: user)

      assert {:ok, settings} =
               Scan.save_settings(%{scan_on: false, address: "clamd:3310"}, actor: root!())

      assert {:error, %Ash.Error.Forbidden{}} =
               Scan.change_settings(settings, %{scan_on: true}, actor: user)

      assert {:ok, []} = Scan.read_settings(actor: user)
      assert Scan.settings().address == "clamd:3310"
    end

    test "need an address that clamd can have, and one at all for the scan to be on" do
      root = root!()

      assert {:error, error} =
               Scan.save_settings(%{scan_on: false, address: "clamd"}, actor: root)

      assert Exception.message(error) =~ "give host:port"

      assert {:error, error} = Scan.save_settings(%{scan_on: true, address: nil}, actor: root)
      assert Exception.message(error) =~ "give the address of clamd"

      assert {:ok, _settings} =
               Scan.save_settings(%{scan_on: true, address: "/run/clamav/clamd.ctl"}, actor: root)
    end

    test "are off with no row" do
      refute Scan.on?()
      assert %{scan_on: false, address: nil} = Scan.settings()
    end
  end

  describe "bin/check" do
    test "notes a scan that is off" do
      assert {:note, "scan", words} = Check.scan()
      assert words =~ "/root/scan"
    end

    test "says whether clamd answers" do
      address = FakeClamd.start(:clean)
      turn_on!(address)
      assert Check.scan() == {:ok, "scan", "clamd at #{address} answers"}

      turn_on!(FakeClamd.nobody())
      assert {:fail, "scan", words} = Check.scan()
      assert words =~ "cannot be reached: econnrefused: each PDF is refused"
    end
  end
end
