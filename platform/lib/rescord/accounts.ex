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

  alias Rescord.Accounts.User

  boundary do
    deps [Rescord]
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Rescord.Accounts.User do
      define :user_by_email, action: :get_by_email, args: [:email], not_found_error?: false
    end

    resource Rescord.Accounts.Token
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
