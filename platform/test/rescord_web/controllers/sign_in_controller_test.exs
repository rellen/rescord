defmodule RescordWeb.SignInControllerTest do
  @moduledoc """
  Holds the sign-in by a link in an email (ADR 0018), and its rules:

    * a request for a link gives the same answer in each case, and does not
      wait for the work (ADR 0019);
    * an address and a client each have a limit (ADR 0020);
    * a link works one time, and only after a press of its button;
    * a sign-out ends each copy of the session.

  The tests change the function that builds a link for the whole node, so
  they do not run beside other tests.
  """

  use RescordWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Rescord.AccountsFixtures
  import Swoosh.TestAssertions

  alias Rescord.Accounts
  alias Rescord.AccountsFixtures.{FailingLink, SlowLink}

  setup %{conn: conn} do
    on_exit(&wait_for_sign_in_tasks/0)

    # The limit of a client counts an address of the network. Each test is a
    # client of its own, or the tests would share one count.
    number = System.unique_integer([:positive])
    client = {10, rem(div(number, 65_536), 256), rem(div(number, 256), 256), rem(number, 256)}

    {:ok, conn: %{conn | remote_ip: client}}
  end

  defp ask(conn, params) do
    conn = post(conn, ~p"/sign-in", params)
    wait_for_sign_in_tasks()
    conn
  end

  # What a person can see of an answer.
  defp answer(conn),
    do: {conn.status, Plug.Conn.get_resp_header(conn, "location"), conn.resp_body}

  defp signed_in?(conn), do: html_response(get(conn, ~p"/"), 200) =~ "You are signed in as"

  describe "a request for a link" do
    test "sends an email with a link to an address that has an account", %{conn: conn} do
      user = user!()

      conn = ask(conn, %{"email" => to_string(user.email)})

      assert redirected_to(conn) == ~p"/sign-in/sent"
      assert_email_sent(fn email -> assert email.to == [{"", to_string(user.email)}] end)
    end

    test "sends nothing to an address that has no account, and makes no user", %{conn: conn} do
      address = unique_address()

      conn = ask(conn, %{"email" => address})

      assert redirected_to(conn) == ~p"/sign-in/sent"
      assert_no_email_sent()
      assert Accounts.user_by_email!(address, authorize?: false) == nil
    end

    test "gives the same answer in each case", %{conn: conn} do
      known = to_string(user!().email)

      answers =
        for params <- [
              %{"email" => known},
              %{"email" => unique_address()},
              %{"email" => "not an address"},
              %{"email" => ""},
              %{"email" => ["a", "list"]},
              %{}
            ] do
          conn |> ask(params) |> answer()
        end

      # Positive control: the known address did get its email.
      assert_email_sent()
      assert [{302, [location], _body}] = Enum.uniq(answers)
      assert location == ~p"/sign-in/sent"
    end

    test "gives that answer when the email cannot be made, and the log has no token", %{
      conn: conn
    } do
      build_links_with(FailingLink, self())
      user = user!()

      {conn, log} =
        with_log(fn -> ask(conn, %{"email" => to_string(user.email)}) end)

      assert redirected_to(conn) == ~p"/sign-in/sent"
      assert_no_email_sent()

      # Positive control: the fault did happen, with the token in its message.
      assert_received {:failing, token}
      assert log =~ "A request for a sign-in link failed"
      refute log =~ token
    end

    test "does not wait for a mail service that is slow", %{conn: conn} do
      build_links_with(SlowLink, self())
      user = user!()

      # The answer is here while the task still waits for the test.
      conn = post(conn, ~p"/sign-in", %{"email" => to_string(user.email)})
      assert redirected_to(conn) == ~p"/sign-in/sent"

      assert_receive {:building, task}, 1_000
      assert Process.alive?(task)
      assert_no_email_sent()

      send(task, :go_on)
      wait_for_sign_in_tasks()
      assert_email_sent()
    end
  end

  describe "the limits" do
    test "an address gets 5 links in 15 minutes, and the answer does not change", %{conn: conn} do
      address = to_string(user!().email)

      answers = for _ <- 1..7, do: conn |> ask(%{"email" => address}) |> answer()

      assert [{302, _, _}] = Enum.uniq(answers)

      for _ <- 1..5, do: assert_email_sent()
      assert_no_email_sent()
    end

    test "the limit of an address does not look at its case", %{conn: conn} do
      address = to_string(user!().email)

      for form <- List.duplicate(address, 3) ++ List.duplicate(String.upcase(address), 4) do
        ask(conn, %{"email" => form})
      end

      for _ <- 1..5, do: assert_email_sent()
      assert_no_email_sent()
    end

    test "a client gets 20 requests in 15 minutes, for any address", %{conn: conn} do
      for _ <- 1..20 do
        assert redirected_to(ask(conn, %{"email" => unique_address()})) == ~p"/sign-in/sent"
      end

      conn = ask(conn, %{"email" => unique_address()})
      assert html_response(conn, 429) =~ "Too many requests"
    end

    test "behind a proxy on the same machine, each client has a limit of its own", %{conn: conn} do
      # Two clients that a proxy on 127.0.0.1 forwards (ADR 0046).
      [first, second] =
        for _ <- 1..2 do
          number = System.unique_integer([:positive])
          "203.0.#{rem(div(number, 256), 256)}.#{rem(number, 256)}"
        end

      behind_proxy = fn client ->
        conn
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> put_req_header("x-forwarded-for", client)
      end

      for _ <- 1..20 do
        assert redirected_to(ask(behind_proxy.(first), %{"email" => unique_address()})) ==
                 ~p"/sign-in/sent"
      end

      assert html_response(ask(behind_proxy.(first), %{"email" => unique_address()}), 429)

      assert redirected_to(ask(behind_proxy.(second), %{"email" => unique_address()})) ==
               ~p"/sign-in/sent"
    end
  end

  describe "a link" do
    setup %{conn: conn} do
      user = user!()
      ask(conn, %{"email" => to_string(user.email)})
      assert_received {:email, email}

      {:ok, user: user, token: token_in(email)}
    end

    test "is for 15 minutes, one time" do
      strategy = AshAuthentication.Info.strategy!(Accounts.User, :magic_link)

      assert strategy.token_lifetime == {15, :minutes}
      assert strategy.single_use_token?
      refute strategy.registration_enabled?
    end

    test "signs nobody in when a program only opens it", %{conn: conn, token: token} do
      for _ <- 1..2 do
        conn = get(conn, ~p"/sign-in/link?#{[token: token]}")
        assert html_response(conn, 200) =~ "Press the button"
        assert Plug.Conn.get_resp_header(conn, "referrer-policy") == ["no-referrer"]
        refute signed_in?(recycle(conn))
      end
    end

    test "signs the person in with the button, and then works no more", %{
      conn: conn,
      user: user,
      token: token
    } do
      get(conn, ~p"/sign-in/link?#{[token: token]}")

      signed_in = post(conn, ~p"/sign-in/link", %{"token" => token})
      assert redirected_to(signed_in) == ~p"/"
      assert html_response(get(recycle(signed_in), ~p"/"), 200) =~ to_string(user.email)

      again = post(build_conn(), ~p"/sign-in/link", %{"token" => token})
      assert html_response(again, 422) =~ "This link does not work"
      refute signed_in?(recycle(again))
    end

    test "does not work with another token", %{conn: conn} do
      for token <- ["", "not a token", nil] do
        conn = post(conn, ~p"/sign-in/link", %{"token" => token})
        assert html_response(conn, 422) =~ "This link does not work"
      end
    end
  end

  describe "a sign-out" do
    test "ends the session, and each copy of it", %{conn: conn} do
      user = user!()
      ask(conn, %{"email" => to_string(user.email)})
      assert_received {:email, email}

      signed_in = post(conn, ~p"/sign-in/link", %{"token" => token_in(email)})
      assert signed_in?(recycle(signed_in))

      # The session names the sockets of its user, so a sign-out closes each
      # page that is open.
      socket_id = RescordWeb.UserAuth.socket_id(user.id)
      assert get_session(signed_in, :live_socket_id) == socket_id
      RescordWeb.Endpoint.subscribe(socket_id)

      signed_out = delete(recycle(signed_in), ~p"/sign-out")
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^socket_id}
      assert redirected_to(signed_out) == ~p"/sign-in"
      # The browser drops the photos that it kept (issue 34).
      assert get_resp_header(signed_out, "clear-site-data") == [~s("cache")]
      refute signed_in?(recycle(signed_out))

      # A copy of the cookie from before the sign-out.
      refute signed_in?(recycle(signed_in))
    end
  end

  test "Phoenix keeps a token out of the log of a request" do
    assert Phoenix.Logger.filter_values(%{"token" => "a-token", "email" => "a@example.com"}) ==
             %{"token" => "[FILTERED]", "email" => "a@example.com"}
  end
end
