defmodule Rescord.Accounts do
  @moduledoc """
  The users of Rescord, and how a user signs in.

  A person signs in with a link by email (ADR 0018). The resources of this
  domain are outside the schemas of the organisations: all organisations share
  the users.

  ## A request for a sign-in link

  `request_sign_in_link/1` starts a task and returns at once, whatever the
  address is (ADR 0019). The task looks the address up, makes the token and
  sends the email. The caller learns nothing: not whether Rescord knows the
  address, and not whether the email left. A fault goes to the log, with no
  token and no link.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  require Logger

  require Ash.Query

  alias Rescord.Accounts.{Grants, Member, Organisation, User}

  boundary do
    deps [Rescord]
    # Another domain holds its own grants, and uses the check (ADR 0024).
    exports [Rescord.Accounts.Grants, Rescord.Accounts.Checks.Granted]
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Rescord.Accounts.User do
      define :user_by_email, action: :get_by_email, args: [:email], not_found_error?: false
      define :roots, action: :roots
      define :make_root, action: :make_root
      define :revoke_root, action: :revoke_root
    end

    resource Rescord.Accounts.Token

    resource Rescord.Accounts.Organisation do
      define :organisations, action: :read
      define :create_organisation, action: :create
      define :rename_organisation, action: :rename

      define :organisation_by_short_name,
        action: :by_short_name,
        args: [:short_name],
        not_found_error?: false
    end

    resource Rescord.Accounts.Member do
      define :members, action: :read
      define :member, action: :read, get_by: [:id], not_found_error?: false
      define :invite_member, action: :invite_member, args: [:email]
      define :invite_administrator, action: :invite_administrator, args: [:email]
      define :make_administrator, action: :make_administrator
      define :make_member, action: :make_member
      define :remove_member, action: :remove
    end
  end

  @doc """
  Makes the first root user, for the email address `address`.

  A person runs this one time, in IEx, when Rescord is first deployed:

      Rescord.Accounts.bootstrap_root("you@example.com")

  It makes the user when there is none for the address. After that the person
  signs in with a link, as each user does.

  Returns `{:error, :root_exists}` when Rescord has a root user already. From
  then on, a root user makes another one.
  """
  @spec bootstrap_root(String.t()) :: {:ok, Ash.Resource.record()} | {:error, term}
  def bootstrap_root(address) when is_binary(address) do
    case roots(authorize?: false) do
      {:ok, []} ->
        User
        |> Ash.Changeset.for_create(:bootstrap_root, %{email: address})
        |> Ash.create(authorize?: false)

      {:ok, _roots} ->
        {:error, :root_exists}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  The organisations that a user can open: each one for a root user, and for
  another user the ones where they are a member.

  A member is in the schema of its organisation, so this looks in each
  schema. That is one query for each organisation.
  """
  @spec organisations_for(Ash.Resource.record()) :: [Ash.Resource.record()]
  def organisations_for(%User{} = user) do
    all = Organisation |> Ash.Query.sort(:name) |> Ash.read!(authorize?: false)

    if user.root?, do: all, else: Enum.filter(all, &member_of(user, &1))
  end

  @doc """
  Opens the organisation with a short name for a user.

  Returns the organisation and the member of the user in it. A root user who
  is not a member gets `nil` for the member. Returns `:error` when there is
  no such organisation, or when the user cannot open it: the two look the
  same from outside.
  """
  @spec organisation_for(Ash.Resource.record(), term) ::
          {:ok, Ash.Resource.record(), Ash.Resource.record() | nil} | :error
  def organisation_for(%User{} = user, short_name) when is_binary(short_name) do
    with %Organisation{} = organisation <-
           organisation_by_short_name!(short_name, authorize?: false),
         member = member_of(user, organisation),
         true <- user.root? or not is_nil(member) do
      {:ok, organisation, member}
    else
      _no -> :error
    end
  end

  def organisation_for(_user, _short_name), do: :error

  @doc """
  What a user is in an organisation: `:root`, or the role of their member.
  """
  @spec role_in(Ash.Resource.record(), Ash.Resource.record() | nil) ::
          :root | :administrator | :member | nil
  def role_in(%User{root?: true}, _member), do: :root
  def role_in(%User{}, %Member{role: role}), do: role
  def role_in(_user, _member), do: nil

  @doc """
  Whether a role can run an action on the members: on one member, or at all.
  A page asks this to decide what to show. The policy decides when the action
  runs.
  """
  @spec role_can?(atom | nil, atom, Ash.Resource.record() | nil) :: boolean
  def role_can?(role, action, member \\ nil)
  def role_can?(:root, _action, _member), do: true
  def role_can?(role, action, nil), do: Grants.scope(role, Member, action) != :none

  def role_can?(role, action, %Member{} = member),
    do: Grants.allows?(role, Member, action, member)

  @doc """
  Whether a role can run an action of a resource at all. Another domain asks
  this about a resource of its own, to decide what a page shows. The policy
  decides when the action runs.
  """
  @spec granted?(atom | nil, module, atom) :: boolean
  def granted?(:root, _resource, _action), do: true
  def granted?(role, resource, action), do: Grants.scope(role, resource, action) != :none

  @doc "The messages of an error of an action, for a person to read."
  @spec error_messages(term) :: [String.t()]
  def error_messages(%{errors: errors}) when is_list(errors) do
    Enum.map(errors, fn
      %{field: field, message: message} when not is_nil(field) and is_binary(message) ->
        "#{field |> to_string() |> String.replace("_", " ") |> String.capitalize()} #{message}"

      %Ash.Error.Forbidden.Policy{} ->
        "You cannot do that"

      error ->
        Exception.message(error)
    end)
  end

  def error_messages(_error), do: ["That did not work"]

  defp member_of(%User{id: user_id}, %Organisation{} = organisation) do
    Member
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.read_one!(tenant: organisation, authorize?: false)
  end

  @sign_in_tasks Rescord.Accounts.SignInTasks

  @doc "The name of the supervisor of the tasks that `request_sign_in_link/1` starts."
  def sign_in_tasks, do: @sign_in_tasks

  @doc """
  Asks for a sign-in link for an email address. Returns `:ok` at once.

  The work happens in a task, and its result does not come back (ADR 0019).
  `address` is whatever the person typed: this function does not look at it.

  Returns `{:error, :busy}` when too many requests are in progress. That
  depends on the load only, and never on the address.
  """
  @spec request_sign_in_link(term) :: :ok | {:error, :busy}
  def request_sign_in_link(address) do
    case Task.Supervisor.start_child(@sign_in_tasks, fn -> send_sign_in_link(address) end) do
      {:ok, _pid} -> :ok
      {:error, :max_children} -> {:error, :busy}
    end
  end

  # Runs in the task. Nothing that it learns goes back to the person who asked.
  defp send_sign_in_link(address) when is_binary(address) do
    strategy = AshAuthentication.Info.strategy!(User, :magic_link)

    case AshAuthentication.Strategy.action(strategy, :request, %{"email" => address}) do
      :ok -> :ok
      {:error, error} -> log_fault(error)
    end
  rescue
    error -> log_fault(error)
  catch
    kind, _reason -> Logger.warning("A request for a sign-in link stopped: #{kind}")
  end

  defp send_sign_in_link(_address), do: :ok

  # The message of an error can hold the address, a token or a link, so the
  # log names only the kind of the error.
  defp log_fault(%Ash.Error.Forbidden{errors: [%AshRateLimiter.LimitExceeded{} | _]}) do
    Logger.info("A request for a sign-in link was over the limit of its address")
  end

  defp log_fault(error) do
    Logger.warning("A request for a sign-in link failed: #{inspect(error.__struct__)}")
  end

  @doc """
  Signs a person in with the token of a sign-in link.

  Returns the user with a session token in its metadata, or `:error`. A token
  works one time, for 15 minutes.
  """
  @spec sign_in_with_link(term) :: {:ok, Ash.Resource.record()} | :error
  def sign_in_with_link(token) when is_binary(token) do
    strategy = AshAuthentication.Info.strategy!(User, :magic_link)

    case AshAuthentication.Strategy.action(strategy, :sign_in, %{"token" => token}) do
      {:ok, %User{} = user} -> {:ok, user}
      _other -> :error
    end
  rescue
    _error -> :error
  end

  def sign_in_with_link(_token), do: :error
end
