defmodule Rescord.Lists do
  @moduledoc """
  The lists of values that describe an entity: the dimensions that an
  organisation can extend (`docs/domain.md`, section 7.2).

  Each dimension has two resources (ADR 0016):

    * the base list, outside the schemas, which holds the shared values;
    * the list of the organisation, in its schema, which holds each value
      that the organisation uses. A row names a shared value, or it is a
      local value with a name of its own (ADR 0025).

  A resident names a row of the list of its organisation.

  The functions of this module take the key of a dimension, such as
  `:species`. `dimensions/0` gives the keys. A key that is not a dimension
  gives `{:error, :no_such_dimension}`.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  alias Rescord.Lists.Base

  boundary do
    # A relationship and a signal listener are checked too (ADR 0066).
    check aliases: true
    deps [Rescord, Rescord.Accounts]
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Rescord.Lists.Base.Species
    resource Rescord.Lists.Base.Breed
    resource Rescord.Lists.Base.Colour
    resource Rescord.Lists.Base.SizeClass
    resource Rescord.Lists.Base.Coat
    resource Rescord.Lists.Base.Temperament
    resource Rescord.Lists.Base.IdentifierKind
    resource Rescord.Lists.Base.GroupKind
    resource Rescord.Lists.Base.LocationKind
    resource Rescord.Lists.Base.Condition
    resource Rescord.Lists.Base.MeasureKind
    resource Rescord.Lists.Base.ProcedureKind
    resource Rescord.Lists.Base.Unit
    resource Rescord.Lists.Base.TaskKind
    resource Rescord.Lists.Base.ItemCategory

    # Another domain names a list of an organisation in a relationship, so
    # each one is public: the `define` exports it (ADR 0066). A page reads a
    # list with `values/2`, which gives the labels and the order.
    resource Rescord.Lists.Species do
      define :species_values, action: :read
    end

    resource Rescord.Lists.Breed do
      define :breed_values, action: :read
    end

    resource Rescord.Lists.Colour do
      define :colour_values, action: :read
    end

    resource Rescord.Lists.SizeClass do
      define :size_class_values, action: :read
    end

    resource Rescord.Lists.Coat do
      define :coat_values, action: :read
    end

    resource Rescord.Lists.Temperament do
      define :temperament_values, action: :read
    end

    resource Rescord.Lists.IdentifierKind do
      define :identifier_kind_values, action: :read
    end

    resource Rescord.Lists.GroupKind do
      define :group_kind_values, action: :read
    end

    resource Rescord.Lists.LocationKind do
      define :location_kind_values, action: :read
    end

    resource Rescord.Lists.Condition do
      define :condition_values, action: :read
    end

    resource Rescord.Lists.MeasureKind do
      define :measure_kind_values, action: :read
    end

    resource Rescord.Lists.ProcedureKind do
      define :procedure_kind_values, action: :read
    end

    resource Rescord.Lists.Unit do
      define :unit_values, action: :read
    end

    resource Rescord.Lists.TaskKind do
      define :task_kind_values, action: :read
    end

    resource Rescord.Lists.ItemCategory do
      define :item_category_values, action: :read
    end
  end

  # The key of each dimension, its name for a person, and its two resources.
  @dimensions [
    {:species, "Species", Base.Species, Rescord.Lists.Species},
    {:breed, "Breed", Base.Breed, Rescord.Lists.Breed},
    {:colour, "Colour", Base.Colour, Rescord.Lists.Colour},
    {:size_class, "Size class", Base.SizeClass, Rescord.Lists.SizeClass},
    {:coat, "Coat", Base.Coat, Rescord.Lists.Coat},
    {:temperament, "Temperament", Base.Temperament, Rescord.Lists.Temperament},
    {:identifier_kind, "Identifier kind", Base.IdentifierKind, Rescord.Lists.IdentifierKind},
    {:group_kind, "Group kind", Base.GroupKind, Rescord.Lists.GroupKind},
    {:location_kind, "Location kind", Base.LocationKind, Rescord.Lists.LocationKind},
    {:condition, "Condition", Base.Condition, Rescord.Lists.Condition},
    {:measure_kind, "Measure kind", Base.MeasureKind, Rescord.Lists.MeasureKind},
    {:procedure_kind, "Procedure kind", Base.ProcedureKind, Rescord.Lists.ProcedureKind},
    {:unit, "Unit", Base.Unit, Rescord.Lists.Unit},
    {:task_kind, "Task kind", Base.TaskKind, Rescord.Lists.TaskKind},
    {:item_category, "Item category", Base.ItemCategory, Rescord.Lists.ItemCategory}
  ]

  @doc "The dimensions, each as `{key, name}`, in the order of a page."
  @spec dimensions() :: [{atom, String.t()}]
  def dimensions, do: Enum.map(@dimensions, fn {key, name, _base, _list} -> {key, name} end)

  @doc """
  The key of a dimension for the text of a parameter of a page, or `:error`.
  This makes no atom from the text.
  """
  @spec dimension(term) :: {:ok, atom} | :error
  def dimension(text) when is_binary(text) do
    Enum.find_value(@dimensions, :error, fn {key, _name, _base, _list} ->
      if Atom.to_string(key) == text, do: {:ok, key}
    end)
  end

  def dimension(_text), do: :error

  @doc "The resource of the list of an organisation for a dimension."
  @spec list(atom) :: module | nil
  def list(key),
    do: Enum.find_value(@dimensions, fn {k, _n, _b, list} -> if k == key, do: list end)

  @doc "The resource of the base list of a dimension."
  @spec base_list(atom) :: module | nil
  def base_list(key),
    do: Enum.find_value(@dimensions, fn {k, _n, base, _l} -> if k == key, do: base end)

  @doc "The resources of the lists of the organisations, for the grants."
  @spec lists() :: [module]
  def lists, do: Enum.map(@dimensions, fn {_key, _name, _base, list} -> list end)

  @doc "The shared values of a dimension, in the order of their names."
  def shared_values(key, opts \\ []) do
    with {:ok, base} <- fetch(&base_list/1, key) do
      base |> Ash.Query.sort(:name) |> Ash.read(opts)
    end
  end

  @doc "Adds a shared value to a dimension. Only a root user can."
  def add_shared_value(key, name, opts \\ []) do
    with {:ok, base} <- fetch(&base_list/1, key) do
      base |> Ash.Changeset.for_create(:add, %{name: name}, opts) |> Ash.create()
    end
  end

  @doc "Gives a shared value a new name. Only a root user can."
  def rename_shared_value(key, id, name, opts \\ []) do
    with {:ok, base} <- fetch(&base_list/1, key),
         {:ok, value} <- Ash.get(base, id, opts) do
      value |> Ash.Changeset.for_update(:rename, %{name: name}, opts) |> Ash.update()
    end
  end

  @doc """
  The values that an organisation uses for a dimension, each with its
  `label`, in the order of the labels. `opts` names the organisation in
  `:tenant`.
  """
  def values(key, opts \\ []) do
    with {:ok, list} <- fetch(&list/1, key) do
      list |> Ash.Query.load(:label) |> Ash.Query.sort(:label) |> Ash.read(opts)
    end
  end

  @doc """
  The values that a form offers for a dimension: each value of the
  organisation that is not retired, with its `label`.
  """
  def offered_values(key, opts \\ []) do
    with {:ok, values} <- values(key, opts) do
      {:ok, Enum.reject(values, & &1.retired)}
    end
  end

  @doc """
  Gives a measure kind of the organisation the units that a measurement of
  it can have: a list of ids of values of the dimension `unit`.
  """
  def set_units(measure_kind_id, unit_ids, opts \\ []) do
    with {:ok, kind} <- Ash.get(Rescord.Lists.MeasureKind, measure_kind_id, opts) do
      kind
      |> Ash.Changeset.for_update(:set_units, %{unit_ids: Enum.uniq(unit_ids)}, opts)
      |> Ash.update()
    end
  end

  @doc """
  The ids of the units that a measurement of a kind can have. An empty list
  means each unit, and so does a kind that is not there.
  """
  @spec unit_ids_of_kind(String.t(), keyword) :: [String.t()]
  def unit_ids_of_kind(measure_kind_id, opts \\ []) do
    case Ash.get(Rescord.Lists.MeasureKind, measure_kind_id, [not_found_error?: false] ++ opts) do
      {:ok, %{unit_ids: unit_ids}} -> unit_ids
      _none -> []
    end
  end

  @doc """
  The unit of measure that a value of the dimension `unit` means, or
  `:error` (ADR 0071). The name of the value is its meaning: the catalogue
  of `Rescord.Units` knows `kg` and `Kilogram`, and it does not know `bag`.
  Rescord does not convert a quantity in a unit that it does not know.

  The value is a row of `Rescord.Lists.Unit` or of its base list, with its
  `label` for a row of an organisation.
  """
  @spec known_unit(term) :: {:ok, Rescord.Units.Unit.t()} | :error
  def known_unit(%{label: %Ash.CiString{} = label}), do: Rescord.Units.parse(to_string(label))
  def known_unit(%{label: label}) when is_binary(label), do: Rescord.Units.parse(label)
  def known_unit(%{name: %Ash.CiString{} = name}), do: Rescord.Units.parse(to_string(name))
  def known_unit(%{name: name}) when is_binary(name), do: Rescord.Units.parse(name)
  def known_unit(_value), do: :error

  @doc """
  Gives an item category of the organisation the number of days before its
  expiry date in which a lot expires soon, or `nil` for the default.
  """
  def set_soon_days(category_id, days, opts \\ []) do
    with {:ok, category} <- Ash.get(Rescord.Lists.ItemCategory, category_id, opts) do
      category
      |> Ash.Changeset.for_update(:set_soon_days, %{soon_days: days}, opts)
      |> Ash.update()
    end
  end

  @doc "Retires a value of an organisation: no form offers it for a new choice."
  def retire_value(key, id, opts \\ []), do: change_value(key, id, :retire, opts)

  @doc "Offers a retired value of an organisation again."
  def restore_value(key, id, opts \\ []), do: change_value(key, id, :restore, opts)

  defp change_value(key, id, action, opts) do
    with {:ok, list} <- fetch(&list/1, key),
         {:ok, value} <- Ash.get(list, id, opts) do
      value |> Ash.Changeset.for_update(action, %{}, opts) |> Ash.update()
    end
  end

  @doc "The shared values of a dimension that the organisation does not use yet."
  def unused_shared_values(key, opts \\ []) do
    with {:ok, values} <- values(key, opts),
         {:ok, shared} <- shared_values(key, Keyword.delete(opts, :tenant)) do
      used = MapSet.new(values, & &1.base_id)
      {:ok, Enum.reject(shared, &MapSet.member?(used, &1.id))}
    end
  end

  @doc "Adds a shared value to the list of an organisation."
  def use_shared_value(key, base_id, opts \\ []) do
    with {:ok, list} <- fetch(&list/1, key) do
      list |> Ash.Changeset.for_create(:add_shared, %{base_id: base_id}, opts) |> Ash.create()
    end
  end

  @doc "Adds a local value, with a name of its own, to the list of an organisation."
  def add_local_value(key, name, opts \\ []) do
    with {:ok, list} <- fetch(&list/1, key) do
      list |> Ash.Changeset.for_create(:add_local, %{name: name}, opts) |> Ash.create()
    end
  end

  @doc "Gives a local value of an organisation a new name."
  def rename_local_value(key, id, name, opts \\ []) do
    with {:ok, list} <- fetch(&list/1, key),
         {:ok, value} <- Ash.get(list, id, opts) do
      value |> Ash.Changeset.for_update(:rename, %{name: name}, opts) |> Ash.update()
    end
  end

  @doc "Whether a role can change the lists of an organisation."
  @spec role_can_change?(atom | nil) :: boolean
  def role_can_change?(role),
    do: Rescord.Accounts.granted?(role, Rescord.Lists.Species, :add_local)

  defp fetch(find, key) do
    case find.(key) do
      nil -> {:error, :no_such_dimension}
      resource -> {:ok, resource}
    end
  end
end
