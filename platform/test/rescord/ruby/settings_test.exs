defmodule Rescord.Ruby.SettingsTest do
  @moduledoc """
  Holds how an organisation turns Ruby on (ADR 0069): who sets it, the
  agreement to the place of the records, each reason that Ruby is not
  available to a person, and the actor of Ruby.

  The test creates an organisation, so it does not run beside others.
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.RubyFixtures

  alias Rescord.{Accounts, Ruby}
  alias Rescord.Ruby.{Actor, Settings}

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    admin = [actor: administrator, tenant: organisation]

    {:ok, asker_role} = Accounts.define_role(%{name: "Asker", powers: [:ruby]}, admin)
    {asker_member, asker} = member!(organisation, :member, administrator)
    {:ok, _member} = Accounts.set_member_role(asker_member, asker_role.id, admin)
    {_, reader} = member!(organisation, :member, administrator)

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     admin: admin,
     asker_role: asker_role,
     asker: asker,
     reader: reader}
  end

  # A provider that the server offers.
  defp offered!(root, values \\ %{}) do
    root |> provider!(values) |> Ruby.change_provider!(%{offered: true}, actor: root)
  end

  # A server of the rescue's own, whose address is its place.
  defp gateway!(root, address \\ "https://llm.example.org/v1") do
    offered!(root, %{
      name: "The gateway",
      kind: :openai_compatible,
      model: "a-model",
      base_url: address
    })
  end

  defp turn_on!(context, provider) do
    [offer] = Enum.filter(Ruby.offers(context.admin), &(&1.id == provider.id))

    Ruby.save_settings(
      %{enabled: true, provider_id: provider.id, agreed_to: offer.place_key},
      context.admin
    )
  end

  defp rows(context),
    do: Ash.read!(Settings, tenant: context.organisation, authorize?: false)

  describe "an organisation with no settings" do
    test "has Ruby off, and nothing to turn on while the server offers no provider", context do
      assert %Settings{enabled: false, retention_days: 90} = Ruby.settings(context.organisation)
      assert Ruby.status(context.organisation) == :not_set_up
      assert Ruby.offers(context.admin) == []
      refute Ruby.available?(context.asker, context.organisation)

      # A provider that the root user does not offer changes nothing.
      provider!(context.root)
      assert Ruby.status(context.organisation) == :not_set_up
    end

    test "has Ruby off when the server offers a provider", context do
      provider = offered!(context.root)

      assert Ruby.status(context.organisation) == :off
      assert [offer] = Ruby.offers(context.admin)
      assert offer.id == provider.id
      assert offer.place == "Anthropic, in the United States and other countries"
      assert offer.place_key == "anthropic"
      assert offer.default_allowance == 2_000
      refute Ruby.available?(context.asker, context.organisation)
    end

    test "sees nothing of a provider but its name and its place", context do
      offered!(context.root)
      [offer] = Ruby.offers(context.admin)

      assert offer |> Map.keys() |> Enum.sort() ==
               [:default_allowance, :id, :kind, :name, :place, :place_key]

      refute inspect(offer) =~ key()
    end
  end

  describe "a person with the power settings" do
    test "turns Ruby on, and agrees to the place of the records", context do
      provider = offered!(context.root)

      assert {:ok, settings} = turn_on!(context, provider)
      assert settings.enabled
      assert settings.provider_id == provider.id
      assert settings.agreed_destination == "anthropic"
      assert settings.agreed_words == "Anthropic, in the United States and other countries"
      assert %DateTime{} = settings.agreed_at
      # The allowance starts at the default of the provider.
      assert settings.allowance == 2_000
      assert settings.retention_days == 90

      assert Ruby.status(context.organisation) == :on
      assert {:ok, read} = Ruby.settings_for(context.admin)
      assert read.id == settings.id
    end

    test "sets the allowance and the days, and the organisation keeps one row", context do
      provider = offered!(context.root)
      {:ok, _settings} = turn_on!(context, provider)

      assert {:ok, changed} =
               Ruby.save_settings(
                 %{enabled: true, provider_id: provider.id, agreed_to: "anthropic"}
                 |> Map.merge(%{allowance: 500, retention_days: 30}),
                 context.admin
               )

      assert changed.allowance == 500
      assert changed.retention_days == 30
      assert [_one] = rows(context)

      for values <- [%{allowance: -1}, %{retention_days: 0}, %{retention_days: 4_000}] do
        assert {:error, _refused} = Ruby.save_settings(values, context.admin)
      end
    end

    test "keeps the time of the agreement while the place stays", context do
      provider = offered!(context.root)
      {:ok, first} = turn_on!(context, provider)

      {:ok, second} =
        Ruby.save_settings(
          %{enabled: true, provider_id: provider.id, agreed_to: "anthropic", allowance: 900},
          context.admin
        )

      assert second.agreed_at == first.agreed_at
    end

    test "cannot turn Ruby on with no provider, or with one that is not offered", context do
      hidden = provider!(context.root)

      assert {:error, none} = Ruby.save_settings(%{enabled: true}, context.admin)
      assert [{:provider_id, "choose the service first"}] = Ruby.problems(none)

      assert {:error, refused} =
               Ruby.save_settings(
                 %{enabled: true, provider_id: hidden.id, agreed_to: "anthropic"},
                 context.admin
               )

      assert [{:provider_id, "choose a service that this server offers"}] =
               Ruby.problems(refused)

      assert {:error, _refused} =
               Ruby.save_settings(
                 %{enabled: true, provider_id: Ash.UUID.generate(), agreed_to: "anthropic"},
                 context.admin
               )

      assert rows(context) == []
    end

    test "cannot agree to a place that the page did not show", context do
      provider = gateway!(context.root)

      for agreed_to <- [nil, "anthropic", "address:https://other.example.org/v1"] do
        assert {:error, refused} =
                 Ruby.save_settings(
                   %{enabled: true, provider_id: provider.id, agreed_to: agreed_to},
                   context.admin
                 )

        assert [{:agreed_to, _words}] = Ruby.problems(refused)
      end

      assert Ruby.status(context.organisation) == :off
    end

    test "turns Ruby off again", context do
      provider = offered!(context.root)
      {:ok, _settings} = turn_on!(context, provider)

      assert {:ok, off} = Ruby.save_settings(%{enabled: false}, context.admin)
      refute off.enabled
      assert Ruby.status(context.organisation) == :off
      refute Ruby.available?(context.asker, context.organisation)
    end
  end

  describe "a person with no power settings" do
    test "reads and changes no settings, and sees no provider", context do
      provider = offered!(context.root)
      {:ok, _settings} = turn_on!(context, provider)

      for user <- [context.asker, context.reader] do
        options = [actor: user, tenant: context.organisation]

        assert Ruby.settings_for(options) == {:error, :forbidden}
        assert Ruby.offers(options) == []
        assert {:ok, nil} = Ruby.read_settings(options)
        assert {:error, %Ash.Error.Forbidden{}} = Ruby.save_settings(%{enabled: false}, options)
      end

      assert Ruby.status(context.organisation) == :on
    end
  end

  describe "Ruby is available" do
    setup context do
      provider = offered!(context.root)
      {:ok, _settings} = turn_on!(context, provider)
      {:ok, provider: provider}
    end

    test "to a member whose role has the power ruby, and to nobody else", context do
      assert Ruby.available?(context.asker, context.organisation)
      assert Ruby.available?(context.administrator, context.organisation)

      refute Ruby.available?(context.reader, context.organisation)
      refute Ruby.available?(user!(), context.organisation)
      refute Ruby.available?(nil, context.organisation)
    end

    test "to a root user only as a member, with the answer of the role", context do
      refute Ruby.available?(context.root, context.organisation)

      {member, root_member} = member!(context.organisation, :member, context.administrator)
      root_member = Ash.Seed.update!(root_member, %{root?: true})
      assert root_member.root?
      refute Ruby.available?(root_member, context.organisation)

      {:ok, _member} = Accounts.set_member_role(member, context.asker_role.id, context.admin)
      assert Ruby.available?(root_member, context.organisation)
    end

    test "in no other organisation", context do
      other = organisation!(context.root, "Banksia Rise")
      {_, their_admin} = member!(other, :administrator, context.root)

      assert Ruby.status(other) == :off
      refute Ruby.available?(their_admin, other)
      refute Ruby.available?(context.asker, other)
      assert Ruby.organisations_with(context.provider) == 1
    end

    test "no more when the role loses the power", context do
      {:ok, _role} = Accounts.revise_role(context.asker_role, %{powers: []}, context.admin)
      refute Ruby.available?(context.asker, context.organisation)
    end

    test "no more when the provider is not offered, or is removed", context do
      {:ok, provider} =
        Ruby.change_provider(context.provider, %{offered: false}, actor: context.root)

      assert Ruby.status(context.organisation) == {:stopped, :provider}
      refute Ruby.available?(context.asker, context.organisation)

      {:ok, provider} = Ruby.change_provider(provider, %{offered: true}, actor: context.root)
      assert Ruby.available?(context.asker, context.organisation)

      :ok = Ruby.remove_provider(provider, actor: context.root)
      assert Ruby.status(context.organisation) == {:stopped, :provider}
      refute Ruby.available?(context.asker, context.organisation)
    end

    test "and an administrator still turns Ruby off, and sets the allowance", context do
      {:ok, _provider} =
        Ruby.change_provider(context.provider, %{offered: false}, actor: context.root)

      # The settings keep the provider that the server took away.
      assert {:error, _refused} =
               Ruby.save_settings(%{enabled: true, allowance: 700}, context.admin)

      assert {:ok, changed} =
               Ruby.save_settings(%{enabled: false, allowance: 700}, context.admin)

      refute changed.enabled
      assert changed.allowance == 700
      assert changed.provider_id == context.provider.id
      assert Ruby.status(context.organisation) == :not_set_up

      # Off, the settings still choose no provider that is not offered.
      hidden = provider!(context.root, %{name: "Another"})

      assert {:error, refused} =
               Ruby.save_settings(%{enabled: false, provider_id: hidden.id}, context.admin)

      assert [{:provider_id, "choose a service that this server offers"}] =
               Ruby.problems(refused)
    end

    test "also after a change of the model, which is no other place", context do
      {:ok, _provider} =
        Ruby.change_provider(context.provider, %{model: "claude-sonnet-5-5"}, actor: context.root)

      assert Ruby.status(context.organisation) == :on
      assert Ruby.available?(context.asker, context.organisation)
    end
  end

  describe "a root user who changes the place of a provider" do
    test "turns Ruby off, until an administrator agrees to the new place", context do
      provider = gateway!(context.root)
      {:ok, first} = turn_on!(context, provider)
      assert first.agreed_destination == "address:https://llm.example.org/v1"
      assert Ruby.available?(context.asker, context.organisation)

      {:ok, moved} =
        Ruby.change_provider(provider, %{base_url: "https://elsewhere.example.org/v1"},
          actor: context.root
        )

      # No row of the organisation is written: the two keys differ.
      assert Ruby.status(context.organisation) == {:stopped, :place}
      refute Ruby.available?(context.asker, context.organisation)
      assert Ruby.settings(context.organisation).agreed_destination == first.agreed_destination

      # The key of the old place does not agree to the new one.
      assert {:error, _refused} =
               Ruby.save_settings(
                 %{enabled: true, provider_id: moved.id, agreed_to: first.agreed_destination},
                 context.admin
               )

      assert {:ok, again} = turn_on!(context, moved)
      assert again.agreed_destination == "address:https://elsewhere.example.org/v1"
      assert again.agreed_words =~ "elsewhere.example.org"
      assert DateTime.compare(again.agreed_at, first.agreed_at) == :gt
      assert Ruby.status(context.organisation) == :on
      assert Ruby.available?(context.asker, context.organisation)
    end
  end

  describe "the actor of Ruby" do
    test "is the member, with the level of a root user off", context do
      assert context.root.root?

      actor = Actor.for(context.root)
      refute actor.root?
      assert actor.id == context.root.id
      assert actor.email == context.root.email

      # With this actor no bypass applies: a root user who is no member
      # reads nothing of an organisation.
      provider = offered!(context.root)
      {:ok, _settings} = turn_on!(context, provider)
      options = [tenant: context.organisation]

      assert {:ok, %Settings{}} = Ruby.read_settings([actor: context.root] ++ options)
      assert {:ok, nil} = Ruby.read_settings([actor: actor] ++ options)
    end
  end
end
