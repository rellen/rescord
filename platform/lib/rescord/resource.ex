defmodule Rescord.Resource do
  @moduledoc """
  The base of every Ash resource of Rescord (ADR 0013).

  Write `use Rescord.Resource` in place of `use Ash.Resource`. It sets the
  defaults that `docs/architecture.md` decides, so a resource states only what
  is its own:

      defmodule Rescord.Residents.ResidentName do
        use Rescord.Resource, domain: Rescord.Residents

        postgres do
          table "resident_names"
        end

        # attributes, actions, relationships ...
      end

  ## The defaults

    * The data layer is `AshPostgres.DataLayer`, and the repo is `Rescord.Repo`.
      The resource names its own table.
    * The resource is in the schema of an organisation
      (`multitenancy do strategy :context end`, ADR 0011).
    * The resource is temporal (ADR 0012): it keeps each version of a record,
      and each read and write happens as of one instant. The period attribute
      is `:valid_at`.
    * The resource keeps a paper trail. On a temporal resource the trail is on
      the version rows (`mode :temporal_inline`), and a version resource lists
      them. On any other resource AshPaperTrail writes to a version resource
      with a table of its own. The policy of a version resource refuses each
      actor (`Rescord.Resource.VersionPolicies`, ADR 0063): a domain reads
      the versions after the record has decided.
    * Each version holds the correlation id of the action call that wrote
      it (`correlation_id`, ADR 0100). A change that runs a nested action
      gives it `context: Rescord.Correlation.context(changeset)`, so that
      both write one id.
    * A destroy archives the row (AshArchival).

  A section that the resource writes again adds to these defaults, and an
  option that it sets again wins.

  ## Options

  Every option of `use Ash.Resource` passes through. These are ours, and each
  must be a literal `true` or `false`:

    * `temporal?` - `false` for a resource that is not temporal. Default `true`.
    * `paper_trail?` - `false` for a resource with no paper trail. Default `true`.
    * `archive?` - `false` for a resource whose destroy deletes the row.
      Default `true`.
    * `shared?` - `true` for a resource that all organisations share, outside
      the schema of an organisation. Default `false`.
    * `table?` - `false` for a resource with no table: it holds generic
      actions only, such as the reports (ADR 0076). It has no data layer of
      Postgres, no history and no archive, and it does not write the section
      `postgres`. A request for it still names an organisation, unless it is
      `shared?`. Default `true`.

  ## A resource with a workflow

  AshStateMachine, and AshWorkflow which builds on it, cannot run on a temporal
  resource: their changes are not temporal safe. `Rescord.Resource.Checks`
  refuses to compile a resource that is temporal and has either extension. So
  such a resource says so:

      use Rescord.Resource,
        domain: Rescord.Tasks,
        temporal?: false,
        extensions: [AshWorkflow, AshOban]

  Its history then comes from its paper trail.

  ## What the domain needs

  The version resources belong to the domain of their resource. A domain adds
  `AshPaperTrail.Domain` to its extensions, with:

      paper_trail do
        include_versions? true
      end
  """

  @flags [temporal?: true, paper_trail?: true, archive?: true, shared?: false, table?: true]

  defmacro __using__(opts) do
    {flags, opts} = split_flags(opts, __CALLER__)
    # A resource with no table has no rows: nothing to version or to archive.
    flags =
      if flags.table?,
        do: flags,
        else: %{flags | temporal?: false, paper_trail?: false, archive?: false}

    {extensions, opts} = Keyword.pop(opts, :extensions, [])

    if not is_list(extensions) do
      raise CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description: "the option :extensions of use Rescord.Resource must be a literal list"
    end

    ours =
      [Rescord.Resource.Checks] ++
        if(flags.paper_trail?,
          do: [AshPaperTrail.Resource, Rescord.Resource.Operations],
          else: []
        ) ++
        if(flags.archive?, do: [AshArchival.Resource], else: [])

    # Spark reads the extensions while it expands `use`, so the list stays a
    # literal: our modules, then the ones that the resource names.
    opts = Keyword.put(opts, :extensions, ours ++ extensions)

    opts =
      if flags.table?, do: Keyword.put_new(opts, :data_layer, AshPostgres.DataLayer), else: opts

    # A resource with a table tells the pages when a record changes (ADR 0096).
    opts =
      if flags.table?,
        do:
          Keyword.update(opts, :notifiers, [Ash.Notifier.PubSub], &([Ash.Notifier.PubSub] ++ &1)),
        else: opts

    quote do
      use Ash.Resource, unquote(opts)

      unquote(postgres(flags))
      unquote(tenancy(flags))
      unquote(temporal(flags))
      unquote(paper_trail(flags))
      unquote(changes(flags, domain_key(opts, __CALLER__)))
    end
  end

  # The part of a topic that names the domain of the resource, such as "tasks".
  defp domain_key(opts, caller) do
    case Macro.expand(Keyword.get(opts, :domain), caller) do
      domain when is_atom(domain) and not is_nil(domain) ->
        Rescord.Changes.key(domain)

      _other ->
        raise CompileError,
          file: caller.file,
          line: caller.line,
          description: "use Rescord.Resource needs the option :domain, as a literal module"
    end
  end

  defp split_flags(opts, caller) do
    if not Keyword.keyword?(opts) do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description: "use Rescord.Resource takes a literal keyword list of options"
    end

    Enum.reduce(@flags, {%{}, opts}, fn {flag, default}, {flags, opts} ->
      {value, opts} = Keyword.pop(opts, flag, default)

      if not is_boolean(value) do
        raise CompileError,
          file: caller.file,
          line: caller.line,
          description:
            "the option #{inspect(flag)} of use Rescord.Resource must be a literal true or false, " <>
              "got: #{Macro.to_string(value)}"
      end

      {Map.put(flags, flag, value), opts}
    end)
  end

  defp postgres(%{table?: false}), do: nil

  defp postgres(_flags) do
    quote do
      postgres do
        repo Rescord.Repo
      end
    end
  end

  defp tenancy(%{shared?: true}), do: nil

  defp tenancy(_flags) do
    quote do
      multitenancy do
        strategy :context
      end
    end
  end

  defp temporal(%{temporal?: false}), do: nil

  defp temporal(_flags) do
    quote do
      temporal do
        strategy :context
        attribute :valid_at
      end
    end
  end

  defp paper_trail(%{paper_trail?: false}), do: nil

  # Each version row of a temporal resource is a version already, so the trail
  # goes on those rows, and holds only the values that the change replaced.
  defp paper_trail(%{temporal?: true}) do
    quote do
      paper_trail do
        mode :temporal_inline
        change_tracking_mode :previous_values
        store_action_name? true
        operation_id_field :correlation_id
        metadata :operation_id, :uuid, allow_nil?: true
        metadata :causation_id, :uuid, allow_nil?: true
        version_resource? true
        version_extensions authorizers: [Ash.Policy.Authorizer]
        mixin Rescord.Resource.VersionPolicies
      end

      # A version row is in the table of the resource. Most rows from before
      # ADR 0100 have no id, so the index holds only the rows that have one.
      postgres do
        custom_indexes do
          index [:correlation_id], where: "correlation_id IS NOT NULL"
        end
      end
    end
  end

  defp paper_trail(_flags) do
    quote do
      paper_trail do
        change_tracking_mode :changes_only
        store_action_name? true
        operation_id_field :correlation_id
        metadata :operation_id, :uuid, allow_nil?: true
        metadata :causation_id, :uuid, allow_nil?: true
        version_extensions authorizers: [Ash.Policy.Authorizer]
        # The policies, and the index of the version table (ADR 0100).
        mixin Rescord.Resource.VersionTable
      end
    end
  end

  defp changes(%{table?: false}, _key), do: nil

  # A shared resource has no tenant, so it has no publication from here: it
  # writes its own, with the attribute that holds the id of the organisation.
  defp changes(%{shared?: true}, _key) do
    quote do
      pub_sub do
        module Rescord.Changes
        prefix unquote(Rescord.Changes.prefix())
        transform &Rescord.Changes.change/1
      end
    end
  end

  defp changes(_flags, key) do
    quote do
      pub_sub do
        module Rescord.Changes
        prefix unquote(Rescord.Changes.prefix())
        transform &Rescord.Changes.change/1

        publish_all :create, [:_tenant, unquote(key)]
        publish_all :update, [:_tenant, unquote(key)]
        publish_all :destroy, [:_tenant, unquote(key)]
      end
    end
  end
end
