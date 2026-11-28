defmodule RescordWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use RescordWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  # A test support module may use any boundary, and any test may use it (ADR 0009).
  use Boundary, top_level?: true, check: [in: false, out: false]

  using do
    quote do
      # The setup checks out the SQL sandbox, so every test here needs
      # Postgres (ADR 0006).
      @moduletag :postgres

      # The default endpoint for testing
      @endpoint RescordWeb.Endpoint

      use RescordWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import RescordWeb.ConnCase
    end
  end

  setup tags do
    Rescord.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  The HTML of a page with a collection of Cinder, after a change of another
  process (ADR 0096). The page asks Cinder to read in the message of the
  change, and Cinder starts its read in a message after that one. The
  first render lets the page take both messages, and the second waits for
  the read.
  """
  @spec render_changes(Phoenix.LiveViewTest.View.t()) :: String.t()
  def render_changes(view) do
    _html = Phoenix.LiveViewTest.render(view)
    Phoenix.LiveViewTest.render_async(view)
  end

  @doc """
  Runs `fun`, which opens a page, so that the page waits a minute before it
  reads again after a change (ADR 0096). In the tests a page reads at once.
  With this, a test holds what a page does when it has not read yet: a
  person presses a button a moment after another person did.

  The wait is a value of the application, so only a test that does not run
  beside others calls this.
  """
  @spec with_slow_changes((-> result)) :: result when result: term
  def with_slow_changes(fun) when is_function(fun, 0) do
    before = Application.fetch_env!(:rescord, RescordWeb.LiveChanges)
    Application.put_env(:rescord, RescordWeb.LiveChanges, wait: :timer.minutes(1))

    try do
      fun.()
    after
      Application.put_env(:rescord, RescordWeb.LiveChanges, before)
    end
  end
end
