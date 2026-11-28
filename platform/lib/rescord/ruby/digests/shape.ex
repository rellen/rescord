defmodule Rescord.Ruby.Digests.Shape do
  @moduledoc """
  What each digest of Ruby shares (ADR 0069): how an argument of the model
  becomes a value, and how a record becomes what a tool result holds.

  A tool result names a record with a `ref` such as `task:<id>`, a `label`
  and, in a list, one line of `detail`. The page makes each link and each
  card from those three, and never from the words of the model. A text
  that a person wrote is under a key that ends in `_text`, which the
  prompt calls data. No result holds a name or an address of a member.

  The tenant of a digest is the organisation in a page, and the name of
  its schema (`"org_<id>"`) in a job. Each function here takes both.

  The arguments are what a model sent: text keys, and any value. A value
  that is none gets `{:error, words}`, and the model reads the words.
  """

  alias Rescord.Accounts

  @doc "The reference of a record: its kind, a colon and its id."
  @spec ref(String.t(), String.t()) :: String.t()
  def ref(kind, id) when is_binary(kind) and is_binary(id), do: kind <> ":" <> id

  @doc "The date of an argument, as `YYYY-MM-DD`. With none, today in the organisation."
  @spec date(term, term) :: {:ok, Date.t()} | {:error, String.t()}
  def date(nothing, tenant) when nothing in [nil, ""], do: {:ok, Accounts.today(tenant)}

  def date(text, _tenant) when is_binary(text) do
    case Date.from_iso8601(String.trim(text)) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, "date: give a date as YYYY-MM-DD"}
    end
  end

  def date(_other, _tenant), do: {:error, "date: give a date as YYYY-MM-DD"}

  @doc "The id of an argument: `nil` for none, and an error for a text that is no id."
  @spec id(term, String.t()) :: {:ok, String.t() | nil} | {:error, String.t()}
  def id(nothing, _name) when nothing in [nil, ""], do: {:ok, nil}

  def id(text, name) when is_binary(text) do
    case Ecto.UUID.cast(String.trim(text)) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, "#{name}: give the id of a record, as another tool returned it"}
    end
  end

  def id(_other, name),
    do: {:error, "#{name}: give the id of a record, as another tool returned it"}

  @doc "One of a closed list of words, or the default with none."
  @spec one_of(term, String.t(), [String.t()], String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def one_of(nothing, _name, _words, default) when nothing in [nil, ""], do: {:ok, default}

  def one_of(value, name, words, _default) do
    if is_binary(value) and value in words,
      do: {:ok, value},
      else: {:error, "#{name}: give one of #{Enum.join(words, ", ")}"}
  end

  @doc """
  An instant in the time zone of the organisation, as ISO 8601 with the
  offset: the model does no arithmetic with time zones.
  """
  @spec local(DateTime.t(), term) :: String.t()
  def local(%DateTime{} = instant, tenant) do
    tenant
    |> Accounts.local_time(instant)
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  @doc "The time of day of an instant in the organisation, such as `08:00`."
  @spec clock(DateTime.t(), term) :: String.t()
  def clock(%DateTime{} = instant, tenant),
    do: tenant |> Accounts.local_time(instant) |> Calendar.strftime("%H:%M")

  @doc "What a task is about: a reference and a label for each subject."
  @spec subjects(map) :: [map]
  def subjects(%{subjects: subjects}) when is_list(subjects) do
    for subject <- subjects, about = subject(subject), not is_nil(about), do: about
  end

  def subjects(_task), do: []

  defp subject(%{resident_id: id, resident: %{} = resident})
       when is_binary(id) and not is_struct(resident, Ash.NotLoaded),
       do: %{ref: ref("resident", id), label: resident.name || "A resident with no name"}

  defp subject(%{group_id: id, group: %{members: members} = group})
       when is_binary(id) and is_list(members),
       do: %{ref: ref("group", id), label: Rescord.Residents.group_name(group)}

  defp subject(%{location_id: id, location: %{name: name}}) when is_binary(id),
    do: %{ref: ref("location", id), label: name}

  # A subject that the member cannot read is not named.
  defp subject(_other), do: nil

  @doc "Whether a task is about this resident: by itself, or as a member of a group."
  @spec about?(map, String.t()) :: boolean
  def about?(%{subjects: subjects}, resident_id) when is_list(subjects) do
    Enum.any?(subjects, fn
      %{resident_id: ^resident_id} -> true
      %{group: %{members: members}} when is_list(members) -> member?(members, resident_id)
      _other -> false
    end)
  end

  def about?(_task, _resident_id), do: false

  defp member?(members, resident_id),
    do: Enum.any?(members, &match?(%{resident_id: ^resident_id}, &1))

  @doc "A text of a person, cut to `limit` characters, or `nil` for none."
  @spec cut(term, pos_integer) :: String.t() | nil
  def cut(text, limit) when is_binary(text) and text != "" do
    if String.length(text) > limit, do: String.slice(text, 0, limit) <> "…", else: text
  end

  def cut(_none, _limit), do: nil
end
