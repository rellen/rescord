defmodule Rescord.Ruby.Digests.Pick do
  @moduledoc """
  Turns what the model sent for a record, an id or a name, into the record
  (ADR 0069). A person says a name, so a digest takes one and searches for
  it itself: the model then needs no call of `find_residents` first.

    * an id, or the `ref` of a result (`resident:<id>`), is read as the
      member, and a record that the member cannot read is none. An id is
      the text of 36 characters: `Ecto.UUID.cast/1` also takes any text of
      16 bytes, and a name can be one;
    * a name is compared with each name, in any case of the letters: one
      that is the same wins, and else each one that holds it;
    * two records or more give `{:choose, result}`: the digest returns the
      result as it is (`choose`, in the order of the names, and
      `more_choices` when there were more than 10), and the model asks the
      person which one.

  Each read runs as the member, with the policy of the page.
  """

  alias Rescord.{Locations, Residents}
  alias Rescord.Ruby.Digests.Shape

  @typedoc "A record, the choices of a name that more than one record has, or words for the model."
  @type picked :: {:ok, struct} | {:choose, map} | {:error, String.t()}

  # The most choices of one name.
  @most 10

  @doc "The resident of an argument, as `options` (the actor and the tenant) may read it."
  @spec resident(term, keyword) :: picked
  def resident(value, options) do
    pick(value, "resident", options,
      # The name is a calculation: a read by id loads it, as a read by name does.
      get: &Residents.resident(&1, Keyword.put(options, :load, Residents.summary())),
      all: fn -> Residents.residents(Keyword.put(options, :load, Residents.summary())) end,
      name: & &1.name,
      choice: fn resident ->
        %{
          ref: Shape.ref("resident", resident.id),
          label: resident.name || "A resident with no name",
          detail: detail([resident.species_label, words(resident.status), arrived(resident)])
        }
      end
    )
  end

  @doc "The location of an argument, as `options` (the actor and the tenant) may read it."
  @spec location(term, keyword) :: picked
  def location(value, options) do
    pick(value, "location", options,
      get: &Locations.location(&1, options),
      all: fn -> Locations.locations(Keyword.put(options, :load, kind: [:label])) end,
      name: & &1.name,
      choice: fn location ->
        %{
          ref: Shape.ref("location", location.id),
          label: location.name,
          detail: detail([label(location.kind)])
        }
      end
    )
  end

  defp pick(value, name, _options, how) when is_binary(value) do
    text = String.trim(value)

    cond do
      text == "" -> {:error, "#{name}: give the id or the name of a #{name}"}
      id = Shape.id_in(text, name) -> by_id(id, name, how)
      true -> by_name(text, name, how)
    end
  end

  defp pick(_value, name, _options, _how),
    do: {:error, "#{name}: give the id or the name of a #{name}"}

  defp by_id(id, name, how) do
    case how[:get].(id) do
      {:ok, %{} = record} ->
        {:ok, record}

      _none ->
        {:error, "#{name}: the records that this member can read hold no #{name} with this id"}
    end
  end

  defp by_name(text, name, how) do
    case how[:all].() do
      {:ok, records} ->
        wanted = String.downcase(text)
        named = Enum.filter(records, &is_binary(how[:name].(&1)))
        same = Enum.filter(named, &(String.downcase(how[:name].(&1)) == wanted))

        matches =
          if same != [],
            do: same,
            else: Enum.filter(named, &String.contains?(String.downcase(how[:name].(&1)), wanted))

        case matches do
          [one] ->
            {:ok, one}

          [] ->
            {:error,
             "#{name}: the records that this member can read hold no #{name} with that name"}

          several ->
            shown = several |> Enum.sort_by(&String.downcase(how[:name].(&1))) |> Enum.take(@most)

            {:choose,
             Shoddy.Maps.compact(%{
               choose: Enum.map(shown, how[:choice]),
               more_choices: if(length(several) > @most, do: length(several) - @most)
             })}
        end

      {:error, error} ->
        {:error, AshAi.Tool.Errors.format(error)}
    end
  end

  @doc "A value of a fixed list in words: `:in_care` is \"in care\"."
  @spec words(atom | nil) :: String.t() | nil
  def words(nil), do: nil
  def words(value) when is_atom(value), do: value |> Atom.to_string() |> String.replace("_", " ")

  @doc "The label of a value of a list, or `nil`."
  @spec label(term) :: String.t() | nil
  def label(%{label: label}) when not is_nil(label), do: to_string(label)
  def label(_none), do: nil

  @doc "One line of detail from its parts. A part that is none is left out."
  @spec detail([term]) :: String.t() | nil
  def detail(parts) do
    case parts |> Enum.reject(&(&1 in [nil, ""])) |> Enum.map(&to_string/1) do
      [] -> nil
      parts -> Enum.join(parts, ", ")
    end
  end

  @doc "A number with its unit, as `14.2 kg`. A value with no unit is the number alone."
  @spec amount(Decimal.t(), String.t() | nil) :: String.t()
  def amount(%Decimal{} = value, unit) do
    [Decimal.to_string(Decimal.normalize(value), :normal), unit]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  @doc "A date as `YYYY-MM-DD`, or `nil`."
  @spec date(Date.t() | nil) :: String.t() | nil
  def date(%Date{} = date), do: Date.to_iso8601(date)
  def date(_none), do: nil

  defp arrived(%{arrived_on: %Date{} = date}), do: "came on #{Date.to_iso8601(date)}"
  defp arrived(_resident), do: nil
end
