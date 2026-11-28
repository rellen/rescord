defmodule Rescord.Calendars do
  @moduledoc """
  The calendar feeds of an organisation (ADR 0074): a member subscribes to
  the tasks and the dates of the organisation in a calendar app.

  A feed is a `Rescord.Calendars.Feed`. Its address holds a token, which is
  the key: a calendar app cannot sign in. `fetch/3` finds the feed of a
  token and says if it still reads, and `entries/4` gives what its calendar
  holds.

  Each domain says what its dated things are, as each domain says what
  needs somebody (ADR 0065):

    * `Rescord.Tasks.calendar/2` - the tasks, at the time that each is due;
    * `Rescord.Residents.calendar/1` - the days on which residents that
      are away are expected back;
    * `Rescord.Inventory.calendar/1` - the expiry dates of the lots that
      have stock.

  Three rules hold.

    * **A feed reads as its owner.** Each read of `entries/4` runs as the
      user of the member, so the policies decide what the feed holds. No
      read for the content passes `authorize?: false`.
    * **A feed reads while its owner could make it.** `fetch/3` asks the
      policy of `subscribe` about the owner at each request. A member who
      was removed, and a role that lost the power, read nothing.
    * **A feed has a limit.** It holds what is dated from `days_back/0`
      days before today, and `limit/0` events at most, the nearest first.

  `Rescord.Calendars.ICalendar` writes the text of a calendar.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  require Ash.Query

  alias Rescord.{Accounts, Inventory, Residents, Tasks}
  alias Rescord.Calendars.{Feed, Token}

  boundary do
    # A relationship and a signal listener are checked too (ADR 0066).
    check aliases: true
    deps [Rescord, Rescord.Accounts, Rescord.Tasks, Rescord.Residents, Rescord.Inventory]
    # The web layer writes the text of a feed with it.
    exports [Rescord.Calendars.ICalendar]
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Rescord.Calendars.Feed do
      define :feeds, action: :read
      define :subscribe, action: :subscribe
      define :revoke_feed, action: :revoke
    end
  end

  # A feed holds what is dated from this number of days before today.
  @days_back 7

  # The events that a feed holds at most.
  @limit 2_000

  # The time between two writes of when a calendar app read a feed. An app
  # can read each few minutes, and a write for each read tells nobody more.
  @mark_every 3_600

  @typedoc """
  One dated thing of a calendar: its kind, the record that a person opens,
  and when it is. A task has the instant `at`, and each other kind has the
  day `on` of the organisation.
  """
  @type entry :: %{
          required(:kind) => :task | :return | :expiry,
          required(:record) => Ash.Resource.record(),
          optional(:at) => DateTime.t(),
          optional(:on) => Date.t(),
          optional(atom) => term
        }

  @doc "The days before today from which a feed holds what is dated."
  @spec days_back() :: pos_integer
  def days_back, do: @days_back

  @doc "The most events that a feed holds."
  @spec limit() :: pos_integer
  def limit, do: @limit

  @doc "The most feeds that one member has at one time."
  @spec feeds_for_each_member() :: pos_integer
  def feeds_for_each_member, do: Rescord.Calendars.Changes.NewToken.limit()

  @doc """
  The token of a feed that `subscribe/2` returned a moment ago, or `nil`
  for a feed that was read: Rescord stores no token.
  """
  @spec token(Ash.Resource.record()) :: String.t() | nil
  def token(%Feed{} = feed), do: Ash.Resource.get_metadata(feed, :token)

  @doc """
  The feeds of a user in the organisation `:tenant`, the oldest first. A
  feed of a member who was removed is left out, also after the person came
  back as a new member: it reads nothing.
  """
  @spec feeds_of(Ash.Resource.record(), keyword) ::
          {:ok, [Ash.Resource.record()]} | {:error, term}
  def feeds_of(%{id: user_id}, opts) do
    Feed
    |> Ash.Query.filter(owner_id == ^user_id)
    |> read_with_member(:member, opts)
  end

  @doc """
  The feeds of the other members that the actor can read, each with its
  member and the email address of that member. A person without the power
  `members` reads none. A feed of a member who was removed is left out: it
  reads nothing.
  """
  @spec feeds_of_others(Ash.Resource.record(), keyword) ::
          {:ok, [Ash.Resource.record()]} | {:error, term}
  def feeds_of_others(%{id: user_id}, opts) do
    Feed
    |> Ash.Query.filter(owner_id != ^user_id)
    |> read_with_member([member: [:email]], opts)
  end

  # A removed member is archived, so the feed of one has no member to load.
  defp read_with_member(query, load, opts) do
    with {:ok, feeds} <-
           query
           |> Ash.Query.sort(inserted_at: :asc, id: :asc)
           |> Ash.Query.load(load)
           |> Ash.read(opts) do
      {:ok, Enum.filter(feeds, &match?(%{member: %{id: _}}, &1))}
    end
  end

  @doc """
  The feed of a token in the organisation with a short name, with the user
  that it reads as and the organisation.

  Returns `:error` for each feed that does not read: an organisation that
  is not there, a text that is no token, a token of no feed, a feed that
  was revoked, a feed of a member who was removed, and a feed of a person
  whose role cannot make a feed now. The caller gives one answer for all
  of them.

  Nobody is signed in: the token is the key. So the organisation, the feed
  and its member are read with no policy, and then the policy of
  `subscribe` is asked about the owner. The content of the feed is read as
  that user (`entries/4`).

  It also writes when the feed was read, once an hour at most.
  """
  @spec fetch(term, term, DateTime.t()) ::
          {:ok, Ash.Resource.record(), Ash.Resource.record(), Ash.Resource.record()} | :error
  def fetch(short_name, token, now \\ DateTime.utc_now())

  def fetch(short_name, token, %DateTime{} = now)
      when is_binary(short_name) and is_binary(token) do
    with true <- Token.shape?(token),
         {:ok, %Accounts.Organisation{} = organisation} <-
           Accounts.organisation_by_short_name(short_name, authorize?: false),
         internal = [tenant: organisation, authorize?: false],
         {:ok, %Feed{} = feed} <-
           Feed
           |> Ash.Query.filter(token_hash == ^Token.hash(token))
           |> Ash.read_one(internal),
         {:ok, %{user: %Accounts.User{} = user}} <-
           Accounts.member(feed.member_id, [load: [:user]] ++ internal),
         true <- Ash.can?({Feed, :subscribe}, user, tenant: organisation) do
      {:ok, mark(feed, now, internal), user, organisation}
    else
      _no_feed -> :error
    end
  end

  def fetch(_short_name, _token, _now), do: :error

  defp mark(feed, now, internal) do
    if is_nil(feed.last_fetched_at) or
         DateTime.diff(now, feed.last_fetched_at) >= @mark_every do
      feed
      |> Ash.Changeset.for_update(:mark, %{at: now}, internal)
      |> Ash.update()
      |> case do
        {:ok, marked} -> marked
        # The mark is a note for a person. A fault in it stops no feed.
        {:error, _error} -> feed
      end
    else
      feed
    end
  end

  @doc """
  What the calendar of a feed holds at `now`, in the order of the time:
  the parts that the feed names, read as `user` in `organisation`.

  A day of the organisation is at the start of that day in the order. The
  list has `limit/0` entries at most, the nearest first.
  """
  @spec entries(Ash.Resource.record(), Ash.Resource.record(), Ash.Resource.record(), DateTime.t()) ::
          {:ok, [entry]} | {:error, term}
  def entries(%Feed{} = feed, user, organisation, now \\ DateTime.utc_now()) do
    first_day = organisation |> Accounts.local_date(now) |> Date.add(-@days_back)
    {from, _next} = Accounts.day_range(organisation, first_day)
    opts = [actor: user, tenant: organisation, limit: @limit]

    with {:ok, tasks} <- tasks(feed, [from: from] ++ opts),
         {:ok, returns} <- part(feed.with_returns, &Residents.calendar/1, first_day, opts),
         {:ok, expiry} <- part(feed.with_expiry, &Inventory.calendar/1, first_day, opts) do
      entries =
        (tasks ++ returns ++ expiry)
        |> Enum.sort_by(&start(&1, organisation), DateTime)
        |> Enum.take(@limit)

      {:ok, entries}
    end
  end

  defp tasks(%Feed{tasks: :none}, _opts), do: {:ok, []}
  defp tasks(%Feed{tasks: :all}, opts), do: Tasks.calendar(:all, opts)
  defp tasks(%Feed{tasks: scope, owner_id: id}, opts), do: Tasks.calendar({scope, id}, opts)

  defp part(true, read, first_day, opts), do: read.([from: first_day] ++ opts)
  defp part(_off, _read, _first_day, _opts), do: {:ok, []}

  defp start(%{at: %DateTime{} = at}, _organisation), do: at

  defp start(%{on: %Date{} = on}, organisation),
    do: organisation |> Accounts.day_range(on) |> elem(0)

  @doc """
  Whether a role can run an action of a feed at all. A page asks this to
  decide what to show. The policy decides when the action runs.
  """
  @spec role_can?(term, atom) :: boolean
  def role_can?(role, action), do: Accounts.granted?(role, Feed, action)

  @doc """
  Whether a role reads the feeds of the other members: the grant of the
  power `members`. A root user does.
  """
  @spec role_reads_each?(term) :: boolean
  def role_reads_each?(:root), do: true

  def role_reads_each?(role),
    do: Accounts.Grants.scope(role, Feed, :read) == {:ok, :all}
end
