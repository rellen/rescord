defmodule Rescord.Ruby.Allowance do
  @moduledoc """
  The use of a month against the allowance of an organisation (ADR 0069).

  The allowance is a sum in whole US cents for a month of the calendar, in
  UTC: the attribute `allowance` of `Rescord.Ruby.Settings`. The use is
  the sum of the rows of `Rescord.Ruby.Usage` of that month, in millionths
  of a dollar.

  `say` asks `room?/1` before each message of a member. The check is
  before a reply, and the price of a reply is known after it: a month can
  end above its allowance by the replies that ran at that moment, at most
  the five of the queue. The spend limit that the owner of the account
  sets at the provider is the backstop.

  No person is here, so these ask no policy: `say` and the job checked who
  asked.
  """

  require Ash.Query

  alias Rescord.Ruby.Usage

  # Millionths of a dollar in one cent.
  @cent 10_000

  @doc """
  Whether the organisation has room for one more question this month. An
  organisation with no allowance has none: nobody asks with no limit.
  """
  @spec room?(term, Date.t()) :: boolean
  def room?(tenant, today \\ Date.utc_today()) do
    case Rescord.Ruby.settings(tenant).allowance do
      cents when is_integer(cents) -> used(tenant, today) < cents * @cent
      nil -> false
    end
  end

  @doc "The use of the month of this day, in millionths of a US dollar."
  @spec used(term, Date.t()) :: non_neg_integer
  def used(tenant, today \\ Date.utc_today()) do
    first = Date.beginning_of_month(today)
    last = Date.end_of_month(today)

    Usage
    |> Ash.Query.filter(day >= ^first and day <= ^last)
    |> Ash.sum!(:cost_microdollars, tenant: tenant, authorize?: false)
    |> Kernel.||(0)
  end

  @doc """
  Adds the counts of one reply to the row of its member, its day and its
  model. `counts` has the keys of `Rescord.Ruby.Usage.counts/0`.
  """
  @spec add!(String.t(), String.t(), map, term, Date.t()) :: :ok
  def add!(user_id, model, counts, tenant, today \\ Date.utc_today()) do
    Usage
    |> Ash.Changeset.for_create(
      :add,
      Map.merge(counts, %{day: today, user_id: user_id, model: model}),
      tenant: tenant,
      authorize?: false
    )
    |> Ash.create!()

    :ok
  end
end
