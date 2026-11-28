defmodule Rescord.PolicySweepTest do
  @moduledoc """
  Tries each action of each resource of each domain as the actors who must
  be refused (ADR 0063).

  The grants say what a role can do (`Rescord.Accounts.Grants`). This test
  holds the other side: what no grant gives, a policy refuses. It asks the
  policies about each action as five actors, in the refuge Wattle Creek:

    * nobody, a request with no actor;
    * a stranger, an administrator of a refuge with no tie to Wattle Creek;
    * a reader, a member of Wattle Creek whose role has no power;
    * a member, with the role `:member` of each refuge;
    * an administrator, with each power.

  An action that an actor can run must be a grant of the role of that
  actor, or an entry of `open_on_purpose/0`, the short list of actions that
  are open on purpose, each with its reason. The version resources are in
  the sweep too.

  A new resource or a new action is thus closed until a person decides
  otherwise. When this test fails for one, do one of three things: give the
  resource a policy that refuses the actor, add the grant to the module of
  grants of its domain, or add the action to `open_on_purpose/0` with the
  reason.

  The test asks with `Ash.can/3`, which runs the policies of the action as
  a run of the action does, and needs no valid input. A read counts as
  refused when the policies forbid it, and when they give it the filter
  `false`. More tests show that the question is a fair one: each grant of a
  role for all records is open to that role, and a root user can run each
  action of a resource that is not closed to all.

  The test creates organisations, so it does not run beside others (see
  `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures

  alias Rescord.Accounts
  alias Rescord.Accounts.{Grants, Member, Organisation, Token, User}
  alias Rescord.Health.Watcher
  alias Rescord.Lists
  alias Rescord.Comments.{Comment, Follow}
  alias Rescord.Notifications.{Notification, NtfyTopic, Preference, PushSubscription}
  alias Rescord.Privacy.InstanceSettings
  alias Rescord.Ruby.{Conversation, Message}
  alias Rescord.Transfers.{Partnership, RefugeKey, RemotePartner, Transfer}

  # The actions that are open on purpose, each as
  # `{resource, action, who, reason}`. `who` is `:signed_in`, each actor who
  # is a user, or `:anyone`, which adds a request with no actor.
  #
  # Keep this list short. An entry is a decision: say why the action is open
  # to a person with no grant for it, and name the test that holds what the
  # action still keeps from that person.
  defp open_on_purpose do
    own_record =
      "A user reads their own record alone: the policy filters by the id of the actor. " <>
        "The test \"a user reads their own record alone\" below holds it."

    own_refuges =
      "The read is filtered to the records of the refuges of the actor (ADR 0042). " <>
        "Rescord.TransfersTest holds that a person of another refuge sees none, " <>
        "and the test \"a stranger reads no partner of another refuge\" below."

    base_list =
      "Each user who is signed in reads the base lists, which all refuges share (ADR 0016)."

    own_device =
      "A device and a topic of ntfy are of one person, in no refuge (ADR 0106): the read is " <>
        "filtered to the actor, and the create sets the actor as the person. " <>
        "Rescord.NotificationsTest holds that a person reads and changes no device of another."

    server_notice =
      "The privacy notice of the server is public, at /privacy with no sign-in (ADR 0105). " <>
        "The one row holds what the operator wrote for the notice: no secret, no person. " <>
        "Only a root user changes it, which this sweep holds for :set and :change."

    [
      {User, :read, :signed_in, own_record},
      {InstanceSettings, :read, :anyone, server_notice},
      {User, :get_by_subject, :signed_in, own_record},
      {User, :get_by_email, :signed_in, own_record},
      {User, :roots, :signed_in, own_record},
      {Partnership, :read, :signed_in, own_refuges},
      {Transfer, :read, :signed_in, own_refuges},
      {RemotePartner, :read, :signed_in, own_refuges},
      {PushSubscription, :read, :signed_in, own_device},
      {PushSubscription, :subscribe, :signed_in, own_device},
      {NtfyTopic, :read, :signed_in, own_device},
      {NtfyTopic, :start, :signed_in, own_device}
    ] ++
      for {key, _name} <- Lists.dimensions() do
        {Lists.base_list(key), :read, :signed_in, base_list}
      end
  end

  # The resources that no actor reaches through a policy, a root user
  # included: the code of Rescord and of AshAuthentication runs their
  # actions. Each version resource is closed too (ADR 0063).
  @closed_to_all [Token, RefugeKey]

  # The resources with no bypass for a root user (ADR 0069): a conversation
  # with the assistant and its messages. A root user reaches them as a
  # member of the refuge, with the grants of the role, and in no other way.
  # The comments that a person follows, their notifications and where they
  # go are of one member too (ADR 0106).
  # The root user of this test is no member of Wattle Creek.
  @members_alone [Conversation, Message, Follow, Notification, Preference]

  # The resources of one person in no refuge (ADR 0106): a root user reaches
  # their own, as each user does, and no other. The code of Rescord runs
  # the rest of their actions. A root user who watches the checks keeps one
  # row of their own too (ADR 0114).
  @each_person_alone [PushSubscription, NtfyTopic, Watcher]

  # Two reads of the sign-in that return nothing without the token of a
  # link, whoever asks: AshAuthentication builds them so.
  @return_nothing [{User, :request_magic_link}, {User, :sign_in_with_magic_link}]

  # What four actions of AshAuthentication, and the read of the comments
  # of an erased person, need before their policies can be
  # asked: without these arguments the action raises while it is built.
  defp needs(Token, :get_token), do: [input: %{jti: "none"}]
  defp needs(Token, :revoke_jti), do: [input: %{jti: "none", subject: "none"}]
  defp needs(Token, :revoke_all_stored_for_subject), do: [input: %{subject: "none"}]

  defp needs(Token, :get_confirmation_changes) do
    strategy = AshAuthentication.Info.strategy!(User, :magic_link)
    [input: %{jti: "none"}, context: %{strategy: strategy}]
  end

  defp needs(Comment, :of_erased_author),
    do: [input: %{author_id: Ash.UUID.generate(), keep_comments: false}]

  defp needs(_resource, _action), do: []

  setup do
    root = root!()
    wattle = organisation!(root, "Wattle Creek")
    banksia = organisation!(root, "Banksia Rise")
    coolibah = organisation!(root, "Coolibah Flat")

    {_, administrator} = member!(wattle, :administrator, root)
    {_, member} = member!(wattle, :member, administrator)
    {reader_record, reader} = member!(wattle, :member, administrator)
    {_, stranger} = member!(coolibah, :administrator, root)

    options = [actor: administrator, tenant: wattle]
    {:ok, no_power} = Accounts.define_role(%{name: "Reader", powers: []}, options)
    {:ok, _} = Accounts.set_member_role(reader_record, no_power.id, options)

    {:ok,
     root: root,
     wattle: wattle,
     banksia: banksia,
     actors: [
       {"nobody", nil, []},
       {"a stranger", stranger, []},
       {"a reader", reader, Grants.grants(no_power)},
       {"a member", member, Grants.grants(:member)},
       {"an administrator", administrator, Grants.grants(:administrator)}
     ]}
  end

  # Each action of each resource of each domain, the version resources
  # included.
  defp actions do
    for domain <- Application.fetch_env!(:rescord, :ash_domains),
        resource <- Ash.Domain.Info.resources(domain),
        action <- Ash.Resource.Info.actions(resource) do
      {resource, action}
    end
  end

  defp version?(resource), do: function_exported?(resource, :resource_version?, 0)

  defp closed_to_all?(resource), do: resource in @closed_to_all or version?(resource)

  # Whether the policies let `actor` run the action, in the refuge Wattle
  # Creek. An action on a record is asked for each record of `records/2`.
  defp open?({resource, action}, actor, context) do
    needs = needs(resource, action.name)

    input =
      if Enum.any?(action.arguments, &(&1.name == :organisation_id)),
        do: %{organisation_id: context.wattle.id},
        else: %{}

    input = Map.merge(input, Keyword.get(needs, :input, %{}))

    options = [
      tenant: context.wattle,
      context: Keyword.get(needs, :context, %{}),
      run_queries?: false,
      alter_source?: true,
      maybe_is: :maybe
    ]

    subjects =
      if action.type in [:update, :destroy],
        do: for(record <- records(resource, context), do: {record, action.name, input}),
        else: [{resource, action.name, input}]

    Enum.any?(subjects, &allowed?(Ash.can(&1, actor, options)))
  end

  # The answer of `Ash.can/3`. `:maybe` means that the record decides, so
  # the action is open to the actor for some record. A read with the filter
  # `false` returns nothing.
  defp allowed?({:ok, false}), do: false
  defp allowed?({:ok, false, _error}), do: false
  defp allowed?({:error, %Ash.Error.Forbidden{}}), do: false
  defp allowed?({:ok, true, %Ash.Query{filter: %Ash.Filter{expression: false}}}), do: false
  defp allowed?({:ok, answer}) when answer in [true, :maybe], do: true
  defp allowed?({:ok, answer, _subject}) when answer in [true, :maybe], do: true
  defp allowed?({:ok, answer, _changeset, _query}) when answer in [true, :maybe], do: true

  # The records that an update or a destroy is asked about. A policy of a
  # resource of a refuge refuses a person who is not a member whatever the
  # record is, so an empty record serves. A resource that all refuges share
  # names its refuges in its attributes, and its policy reads them: its
  # record is one of Wattle Creek, from each side. An organisation and a
  # user are the ones of the setup, because a check reads their id.
  defp records(Organisation, context), do: [context.wattle]
  defp records(User, context), do: [context.root]

  defp records(resource, %{wattle: wattle, banksia: banksia}) do
    names = resource |> Ash.Resource.Info.attributes() |> Enum.map(& &1.name)

    cond do
      :from_organisation_id in names and :to_organisation_id in names ->
        [
          struct(resource, from_organisation_id: wattle.id, to_organisation_id: banksia.id),
          struct(resource, from_organisation_id: banksia.id, to_organisation_id: wattle.id)
        ]

      :organisation_id in names ->
        [struct(resource, organisation_id: wattle.id)]

      true ->
        [struct(resource)]
    end
  end

  defp name({resource, action}),
    do: "#{inspect(resource)} #{inspect(action.name)} (#{action.type})"

  defp listed(actions), do: actions |> Enum.map(&("    " <> name(&1))) |> Enum.join("\n")

  describe "each action of each resource" do
    test "is refused to an actor with no grant for it, but for the ones open on purpose",
         context do
      on_purpose = open_on_purpose()
      all = actions()

      # For each actor: the actions that are open with no reason, and the
      # entries of the list that are refused, which are notes that tell a lie.
      found =
        for {who, actor, grants} <- context.actors do
          granted = MapSet.new(grants, fn {resource, action, _scope} -> {resource, action} end)

          on_purpose_for_actor =
            for {resource, action, to, _reason} <- on_purpose,
                to == :anyone or not is_nil(actor),
                into: MapSet.new(),
                do: {resource, action}

          open = all |> Enum.filter(&open?(&1, actor, context)) |> MapSet.new()
          key = fn {resource, action} -> {resource, action.name} end

          unexpected =
            Enum.filter(all, fn pair ->
              pair in open and key.(pair) not in granted and
                key.(pair) not in on_purpose_for_actor
            end)

          stale = Enum.filter(all, &(key.(&1) in on_purpose_for_actor and &1 not in open))
          {who, unexpected, stale}
        end

      unexpected =
        for {who, [_ | _] = actions, _stale} <- found,
            do: "  #{who} can run:\n#{listed(actions)}"

      assert unexpected == [], """
      No grant and no entry of open_on_purpose/0 gives these actions to these actors:

      #{Enum.join(unexpected, "\n\n")}

      Give the resource a policy that refuses the actor, add the grant to the grants of
      its domain, or add the action to open_on_purpose/0 in this file with the reason.
      """

      stale =
        for {who, _unexpected, [_ | _] = actions} <- found,
            do: "  #{who} cannot run:\n#{listed(actions)}"

      assert stale == [], """
      open_on_purpose/0 names actions that are refused. Take them out:

      #{Enum.join(stale, "\n\n")}
      """
    end

    test "that open_on_purpose/0 names exists, and has a reason" do
      for {resource, action, who, reason} <- open_on_purpose() do
        assert Ash.Resource.Info.action(resource, action),
               "#{inspect(resource)} has no action #{inspect(action)}"

        assert who in [:anyone, :signed_in]
        assert String.length(reason) > 20
      end
    end
  end

  describe "the question is a fair one:" do
    # A grant with a scope other than `:all` holds some records and not
    # others, such as the entries that the actor wrote. The record decides,
    # and the tests of its domain hold it.
    test "each grant of a role is an action that the role can run", context do
      for {who, actor, grants} <- context.actors, {resource, name, scope} <- grants do
        action = Ash.Resource.Info.action(resource, name)
        assert action, "a grant names #{inspect(resource)} #{inspect(name)}, which is no action"

        assert scope != :all or open?({resource, action}, actor, context),
               "#{who} has the grant #{name({resource, action})}, and the policies refuse it"
      end
    end

    test "a root user can run each action of a resource that is not closed to all", context do
      refused =
        for {resource, action} = pair <- actions(),
            not closed_to_all?(resource),
            resource not in @members_alone,
            resource not in @each_person_alone,
            {resource, action.name} not in @return_nothing,
            not open?(pair, context.root, context),
            do: pair

      assert refused == [], "a root user cannot run:\n\n#{listed(refused)}"
    end

    test "a root user cannot run an action of a resource that is closed to all", context do
      open =
        for {resource, _action} = pair <- actions(),
            closed_to_all?(resource),
            open?(pair, context.root, context),
            do: pair

      assert open == [], "a root user can run:\n\n#{listed(open)}"
    end

    test "a root user who is no member runs no action of a resource of the members alone",
         context do
      assert Accounts.Checks.Granted.role_of(context.root, context.wattle) == nil

      open =
        for {resource, _action} = pair <- actions(),
            resource in @members_alone,
            open?(pair, context.root, context),
            do: pair

      assert open == [], "a root user who is no member can run:\n\n#{listed(open)}"
    end

    test "the sweep holds the version resources", _context do
      versions =
        for {resource, _action} <- actions(), version?(resource), uniq: true, do: resource

      assert Rescord.Residents.Resident.Version in versions
      assert Rescord.Tasks.Task.Version in versions
    end
  end

  describe "an action that is open on purpose keeps the rest from the actor:" do
    test "a user reads their own record alone", context do
      [_nobody, {_, stranger, _}, {_, reader, _} | _] = context.actors

      for user <- [stranger, reader] do
        assert {:ok, [%{id: id}]} = Ash.read(User, actor: user)
        assert id == user.id
        assert {:ok, []} = Accounts.roots(actor: user)

        assert {:ok, nil} = Accounts.user_by_email(context.root.email, actor: user)
      end

      assert {:ok, []} = Ash.read(User, actor: nil)
    end

    test "a stranger reads no partner of another refuge", context do
      [_nobody, {_, stranger, _}, {_, reader, _} | _] = context.actors

      Ash.Seed.seed!(RemotePartner, %{
        organisation_id: context.wattle.id,
        refuge_id: Ash.UUID.generate(),
        name: "Mulga Downs",
        sign_public: <<1>>,
        box_public: <<2>>,
        fingerprint: "none"
      })

      Ash.Seed.seed!(Partnership, %{
        from_organisation_id: context.wattle.id,
        to_organisation_id: context.banksia.id
      })

      for resource <- [RemotePartner, Partnership] do
        assert {:ok, [_one]} = Ash.read(resource, actor: reader)
        assert {:ok, []} = Ash.read(resource, actor: stranger)
        assert {:ok, []} = Ash.read(resource, actor: nil)
      end
    end

    # The setup made roles and members, so each of the two has versions: a
    # role keeps them in a table of its own, and a member on its own rows.
    test "a version is read by the domain alone, after the record decides", context do
      [_nobody, {_, stranger, _}, _reader, _member, {_, administrator, _}] = context.actors

      for resource <- [Accounts.Role, Member] do
        version = AshPaperTrail.Resource.Info.version_resource(resource)

        assert {:ok, [_ | _]} = Ash.read(version, tenant: context.wattle, authorize?: false)

        for actor <- [administrator, stranger, context.root, nil] do
          assert {:ok, []} = Ash.read(version, actor: actor, tenant: context.wattle)
        end
      end
    end
  end
end
