defmodule RescordWeb.ObanWebTest do
  @moduledoc """
  Oban Web at `/root/oban` (ADR 0110): only a root user opens it, its
  files too, and a root user may cancel and retry a job and pause a queue,
  and take no other action.

  Oban Web reads the state of an Oban that runs: its notifier and
  `Oban.Met`. The tests run Oban in its testing mode, which starts
  neither, so a test that opens the page runs an instance of its own with
  the same name, with no queue and no plugin, and gives the instance of the
  tests back after it.

  Not async: an organisation makes a schema, and the instance of Oban is
  of the node.
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Phoenix.LiveViewTest,
    only: [
      live: 2,
      element: 2,
      has_element?: 1,
      render_click: 1,
      render: 1,
      render_click: 3,
      with_target: 2
    ]

  import Rescord.AccountsFixtures

  alias RescordWeb.ObanResolver

  setup do
    root = root!()
    organisation = organisation!(root)
    {_member, administrator} = member!(organisation, :administrator, root)
    {_member, member} = member!(organisation, :member, root)
    %{root: root, administrator: administrator, member: member}
  end

  describe "who opens it" do
    test "nobody who is signed out" do
      assert redirected_to(get(build_conn(), ~p"/root/oban")) == "/"
      assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), ~p"/root/oban")
    end

    test "no member and no administrator of an organisation", context do
      for user <- [context.member, context.administrator] do
        conn = sign_in(build_conn(), user)

        assert redirected_to(get(conn, ~p"/root/oban")) == "/"
        assert redirected_to(get(conn, ~p"/root/oban/jobs")) == "/"
        assert redirected_to(get(conn, ~p"/root/oban/queues")) == "/"
      end
    end

    test "not even the files of the page", %{member: member} do
      conn = sign_in(build_conn(), member)

      for path <- ["/root/oban/css-x", "/root/oban/js-x", "/root/oban/fonts/inter-x"] do
        assert redirected_to(get(conn, path)) == "/"
      end
    end

    test "the hook refuses a page that connects past the plug", %{member: member} do
      # A LiveView that connects has the session, and no plug runs.
      session = build_conn() |> sign_in(member) |> Plug.Conn.get_session()
      socket = %Phoenix.LiveView.Socket{endpoint: RescordWeb.Endpoint, router: RescordWeb.Router}

      assert {:halt, %{redirected: {:redirect, %{to: "/"}}}} =
               RescordWeb.UserAuth.on_mount(:require_root, %{}, session, socket)
    end

    test "a root user, from the link of the root page", %{root: root} do
      running_oban()

      build_conn()
      |> sign_in(root)
      |> visit(~p"/root")
      |> click(main() |> link("Watch the background jobs, in Oban Web"))
      |> assert_path("/root/oban")

      conn = sign_in(build_conn(), root)
      assert {:ok, _view, _html} = live(conn, ~p"/root/oban/queues")
      html = conn |> get(~p"/root/oban/jobs") |> html_response(200)

      # The page loads its stylesheet and its script from this server, below
      # its own path.
      files =
        Regex.scan(~r{(?:href|src)="(/root/oban/(?:css|js)-[^"]+)"}, html,
          capture: :all_but_first
        )

      assert length(files) == 2

      for [path] <- files do
        assert conn |> get(path) |> response(200) != ""
      end
    end
  end

  describe "what a root user may do" do
    test "cancel a job, and not delete one", %{root: root} do
      running_oban()
      job = Oban.insert!(Rescord.Notifications.Workers.Prune.new(%{}))
      {:ok, view, _html} = build_conn() |> sign_in(root) |> live(~p"/root/oban/jobs/#{job.id}")

      # The button of a delete is off, and its event does nothing.
      assert view |> element("#detail-delete[disabled]") |> has_element?()
      # The component sends the action to the page, which runs it after the
      # click: a render waits for it.
      view |> with_target("#job-details") |> render_click("delete", %{})
      render(view)
      assert %Oban.Job{state: "available"} = Rescord.Repo.reload(job)

      view |> element("#detail-cancel") |> render_click()
      render(view)
      assert %Oban.Job{state: "cancelled"} = Rescord.Repo.reload(job)
    end

    test "the resolver keeps only the id of the user", %{root: root} do
      conn = Plug.Conn.assign(build_conn(), :current_user, root)
      assert ObanResolver.resolve_user(conn) == %{id: root.id, root?: true}
    end

    test "the resolver refuses anyone who is not a root user", context do
      for user <- [nil, context.member, context.administrator] do
        conn = Plug.Conn.assign(build_conn(), :current_user, user)
        user = ObanResolver.resolve_user(conn)

        assert user == nil
        assert ObanResolver.resolve_access(user) == {:forbidden, "/"}
      end
    end

    test "cancel, retry and pause, and nothing else", %{root: root} do
      access = ObanResolver.resolve_access(%{id: root.id, root?: true})

      for action <- [:cancel_jobs, :retry_jobs, :pause_queues] do
        assert Oban.Web.Helpers.can?(action, access), "#{action} is off"
      end

      for action <- [
            :delete_jobs,
            :insert_jobs,
            :update_jobs,
            :scale_queues,
            :stop_queues,
            :insert_crons,
            :update_crons,
            :pause_crons,
            :delete_crons,
            :insert_pruners,
            :update_pruners,
            :pause_pruners,
            :delete_pruners,
            :cancel_workflows,
            :retry_workflows
          ] do
        refute Oban.Web.Helpers.can?(action, access), "#{action} is on"
      end
    end
  end

  test "the database has the count estimate of Oban Met, from a migration" do
    assert Application.get_env(:oban_met, :reporter)[:auto_migrate] == false

    assert %{rows: [[count]]} =
             Rescord.Repo.query!("SELECT public.oban_count_estimate('available', 'default')")

    assert is_integer(count)
  end

  # An Oban that runs, in place of the one of the tests, for this test.
  # ExUnit stops what `start_supervised!/1` started before it runs the
  # function of `on_exit/1`, so the name is free again then.
  defp running_oban do
    :ok = Supervisor.terminate_child(Rescord.Supervisor, Oban)
    on_exit(fn -> {:ok, _pid} = Supervisor.restart_child(Rescord.Supervisor, Oban) end)

    start_supervised!(
      {Oban,
       name: Oban,
       repo: Rescord.Repo,
       testing: :disabled,
       queues: false,
       plugins: false,
       peer: false,
       notifier: Oban.Notifiers.PG,
       stage_interval: :infinity}
    )
  end
end
