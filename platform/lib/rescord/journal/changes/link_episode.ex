defmodule Rescord.Journal.Changes.LinkEpisode do
  @moduledoc """
  Says which condition of the resident a journal entry is about: the
  episode of the entry (ADR 0083). The change runs before the write of the
  entry, in the same transaction and as of the same instant.

  For a new entry (`write`):

    * an entry that names an episode keeps it. The episode is one of the
      same resident, and for a diagnosis it has the condition of the
      diagnosis;
    * an addendum with no episode gets the one of the entry that it adds to;
    * a diagnosis with no episode joins the ongoing episode of its
      condition, or starts one when the resident has none. The first day of
      a new episode is the argument `onset_on`, or the day of the entry in
      the time zone of the organisation;
    * a dose with no episode gets the one of its prescription.

  For a correction (`correct`):

    * a change of `episode_id` is held to the same rules;
    * a new condition for a diagnosis that has an episode: when the
      diagnosis is the only one of its episode, the episode gets the new
      condition, and in each other case the diagnosis moves to the episode
      of the new condition, as a new diagnosis does.

  With the option `track: true` (`track`) the change gives an episode to a
  diagnosis that has none: one from before Rescord had episodes.

  The policy of the entry decided that the actor can run the action. The
  episode is a part of that action, so the change reads and writes it with
  no second decision, and names the actor for the paper trail.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Rescord.Journal.{Diagnosis, Episode, JournalEntry, Prescription}

  # The change reads and writes through Ash only, as of the instant of the
  # action, and it does not read the clock.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      options = options(changeset, context)

      cond do
        opts[:track] -> track(changeset, options)
        changeset.action_type == :create -> written(changeset, options)
        true -> corrected(changeset, options)
      end
    end)
  end

  # --- a new entry

  defp written(changeset, options) do
    kind = Ash.Changeset.get_attribute(changeset, :kind)
    follows_id = Ash.Changeset.get_attribute(changeset, :follows_id)
    condition_id = argument(changeset, :condition_id)

    cond do
      Ash.Changeset.get_attribute(changeset, :episode_id) ->
        named(changeset, if(kind == :diagnosis and is_nil(follows_id), do: condition_id), options)

      follows_id ->
        put(changeset, episode_of_entry(follows_id, options))

      kind == :diagnosis and condition_id ->
        join_or_start(changeset, condition_id, options)

      kind == :dose ->
        put(changeset, episode_of_prescription(argument(changeset, :prescription_id), options))

      true ->
        changeset
    end
  end

  # --- a correction

  defp corrected(changeset, options) do
    entry = changeset.data
    diagnosis? = entry.kind == :diagnosis and is_nil(entry.follows_id)
    old = if diagnosis?, do: condition_of(entry, options)
    new = if diagnosis?, do: argument(changeset, :condition_id)

    cond do
      Ash.Changeset.changing_attribute?(changeset, :episode_id) ->
        case Ash.Changeset.get_attribute(changeset, :episode_id) do
          nil -> changeset
          _id -> named(changeset, if(diagnosis?, do: new || old), options)
        end

      is_nil(new) or new == old or is_nil(entry.episode_id) ->
        changeset

      only_diagnosis?(entry, options) ->
        rename(changeset, entry.episode_id, new, options)

      true ->
        join_or_start(changeset, new, options)
    end
  end

  # --- a diagnosis from before Rescord had episodes

  defp track(changeset, options) do
    entry = changeset.data

    cond do
      entry.kind != :diagnosis or entry.follows_id ->
        Ash.Changeset.add_error(changeset, field: :kind, message: "is not a diagnosis")

      entry.episode_id ->
        Ash.Changeset.add_error(changeset, field: :episode_id, message: "is tracked already")

      true ->
        case condition_of(entry, options) do
          nil -> Ash.Changeset.add_error(changeset, field: :kind, message: "names no condition")
          condition_id -> join_or_start(changeset, condition_id, options)
        end
    end
  end

  # --- the rules

  # The entry names an episode: one of its resident, and of the condition
  # `condition_id` when the entry is a diagnosis.
  defp named(changeset, condition_id, options) do
    id = Ash.Changeset.get_attribute(changeset, :episode_id)
    resident_id = Ash.Changeset.get_attribute(changeset, :resident_id)

    case Ash.get(Episode, id, [not_found_error?: false] ++ options) do
      {:ok, %Episode{resident_id: ^resident_id} = episode} ->
        if is_nil(condition_id) or episode.condition_id == condition_id do
          changeset
        else
          Ash.Changeset.add_error(changeset,
            field: :episode_id,
            message: "is another condition than the one of the diagnosis"
          )
        end

      {:ok, _other} ->
        Ash.Changeset.add_error(changeset,
          field: :episode_id,
          message: "is not a condition of this resident"
        )

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  # The ongoing episode of the condition, the newest first day first, or a
  # new one.
  defp join_or_start(changeset, condition_id, options) do
    resident_id = Ash.Changeset.get_attribute(changeset, :resident_id)

    ongoing =
      Episode
      |> Ash.Query.filter(
        resident_id == ^resident_id and condition_id == ^condition_id and is_nil(ended_on)
      )
      |> Ash.Query.sort(started_on: :desc, id: :asc)
      |> Ash.Query.limit(1)
      |> Ash.read(options)

    case ongoing do
      {:ok, [episode]} ->
        put(changeset, episode.id)

      {:ok, []} ->
        Episode
        |> Ash.Changeset.for_create(
          :start,
          %{
            resident_id: resident_id,
            condition_id: condition_id,
            started_on: argument(changeset, :onset_on) || day_of(changeset),
            chronic: argument(changeset, :chronic) || false
          },
          options
        )
        |> Ash.create()
        |> case do
          {:ok, episode} -> put(changeset, episode.id)
          {:error, error} -> Ash.Changeset.add_error(changeset, error)
        end

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp rename(changeset, episode_id, condition_id, options) do
    with {:ok, %Episode{} = episode} <-
           Ash.get(Episode, episode_id, [not_found_error?: false] ++ options),
         {:ok, _episode} <-
           episode
           |> Ash.Changeset.for_update(:rename, %{condition_id: condition_id}, options)
           |> Ash.update() do
      changeset
    else
      # The episode was removed: the diagnosis is about no condition.
      {:ok, nil} -> changeset
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  # Whether no other diagnosis names the episode of this one.
  defp only_diagnosis?(entry, options) do
    JournalEntry
    |> Ash.Query.filter(
      episode_id == ^entry.episode_id and kind == :diagnosis and is_nil(follows_id) and
        id != ^entry.id
    )
    |> Ash.Query.limit(1)
    |> Ash.read!(options) == []
  end

  # The day of the entry in the time zone of the organisation.
  defp day_of(changeset) do
    Rescord.Accounts.local_date(
      changeset.tenant,
      Ash.Changeset.get_attribute(changeset, :happened_at)
    )
  end

  defp condition_of(entry, options) do
    Diagnosis
    |> Ash.Query.filter(entry_id == ^entry.id)
    |> Ash.read_one!(options)
    |> case do
      nil -> nil
      diagnosis -> diagnosis.condition_id
    end
  end

  defp episode_of_entry(id, options) do
    case Ash.get!(JournalEntry, id, [not_found_error?: false] ++ options) do
      nil -> nil
      entry -> entry.episode_id
    end
  end

  defp episode_of_prescription(nil, _options), do: nil

  defp episode_of_prescription(id, options) do
    case Ash.get!(Prescription, id, [not_found_error?: false] ++ options) do
      nil -> nil
      prescription -> episode_of_entry(prescription.entry_id, options)
    end
  end

  defp put(changeset, nil), do: changeset
  defp put(changeset, id), do: Ash.Changeset.force_change_attribute(changeset, :episode_id, id)

  defp argument(changeset, name) do
    case Ash.Changeset.fetch_argument(changeset, name) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp options(changeset, context) do
    base = [
      actor: context.actor,
      tenant: changeset.tenant,
      context: Rescord.Correlation.context(changeset),
      authorize?: false
    ]

    case changeset.as_of do
      %DateTime{} = instant -> [as_of: instant] ++ base
      _not_set -> base
    end
  end
end
