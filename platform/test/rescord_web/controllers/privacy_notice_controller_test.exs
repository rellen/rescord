defmodule RescordWeb.PrivacyNoticeControllerTest do
  @moduledoc """
  Holds the privacy notices (ADR 0105): a person with no sign-in reads the
  notice of an organisation at the link of its random notice id and the
  notice of the server at `/privacy`; a notice with a blank says that it is
  not finished; an unknown id, and the id of the organisation itself, find
  nothing; a new notice id ends the old link.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Rescord.AccountsFixtures

  alias Rescord.{Accounts, Privacy}

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {:ok, root: root, organisation: organisation, administrator: administrator}
  end

  defp fill_in!(context) do
    {:ok, _} =
      Privacy.save_instance_settings(
        %{
          operator_name: "Example Hosting",
          operator_contact: "operator@example.org",
          hosting: "Australia",
          mail_provider: "Example Mail"
        },
        actor: context.root
      )

    {:ok, _} =
      Privacy.save_settings(
        %{contact_name: "Jo", contact_email: "privacy@example.org", authority: "the OAIC"},
        actor: context.administrator,
        tenant: context.organisation
      )
  end

  test "the notice of an organisation says that it is not finished while a blank is empty",
       context do
    html =
      context.conn |> get(~p"/privacy/#{context.organisation.notice_id}") |> html_response(200)

    assert html =~ "has not finished this notice yet"
    refute html =~ "Your rights"
  end

  test "a person with no sign-in reads the filled notice of an organisation", context do
    fill_in!(context)

    html =
      context.conn |> get(~p"/privacy/#{context.organisation.notice_id}") |> html_response(200)

    assert html =~ "How Wattle Creek uses your data in Rescord"
    assert html =~ "Example Hosting"
    assert html =~ "privacy@example.org"
    assert html =~ "the OAIC"
    assert html =~ "Your rights"
    refute html =~ "has not finished"
  end

  test "an unknown id, a word, and the id of the organisation find no notice", context do
    assert context.conn |> get(~p"/privacy/#{Ecto.UUID.generate()}") |> html_response(404)
    assert context.conn |> get(~p"/privacy/wattle") |> html_response(404)
    assert context.conn |> get(~p"/privacy/#{context.organisation.id}") |> html_response(404)
  end

  test "a new notice id ends the old link", context do
    old = context.organisation.notice_id

    {:ok, organisation} =
      Accounts.new_notice_id(context.organisation, actor: context.administrator)

    assert organisation.notice_id != old
    assert organisation.notice_id != organisation.id
    assert context.conn |> get(~p"/privacy/#{old}") |> html_response(404)
    assert context.conn |> get(~p"/privacy/#{organisation.notice_id}") |> html_response(200)
  end

  test "a member with no power makes no new notice id", context do
    {_, member} = member!(context.organisation, :member, context.administrator)

    assert {:error, %Ash.Error.Forbidden{}} =
             Accounts.new_notice_id(context.organisation, actor: member)
  end

  test "the notice of the server names the operator once it is filled in", context do
    html = context.conn |> get(~p"/privacy") |> html_response(200)
    assert html =~ ~s(id="notice-missing")

    fill_in!(context)

    html = context.conn |> get(~p"/privacy") |> html_response(200)
    assert html =~ "Example Hosting"
    assert html =~ "operator@example.org"
    refute html =~ ~s(id="notice-missing")
  end
end
