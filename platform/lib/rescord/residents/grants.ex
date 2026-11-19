defmodule Rescord.Residents.Grants do
  @moduledoc """
  What a role can do with the residents of an organisation (ADR 0024).

  Each role reads each fact. The power `:residents` is the care of the
  residents, the daily work of each member: their stay, their families and
  their groups. The power `:remove_residents` removes a resident that was
  recorded by mistake, and only the administrators have it at first
  (ADR 0040). It writes
  the name, the desex status and the ties only through the resident.
  """

  @behaviour Rescord.Accounts.Grants

  alias Rescord.Residents.{
    Absence,
    Arrival,
    Departure,
    Family,
    FamilyMember,
    Group,
    GroupMember,
    ParentLink,
    Resident,
    ResidentBreed,
    ResidentColour,
    ResidentDesexStatus,
    ResidentIdentifier,
    ResidentName,
    ResidentTemperament
  }

  @resources [
    Resident,
    ResidentName,
    ResidentDesexStatus,
    ResidentBreed,
    ResidentColour,
    ResidentTemperament,
    ResidentIdentifier,
    Arrival,
    Departure,
    Absence,
    ParentLink,
    Family,
    FamilyMember,
    Group,
    GroupMember
  ]

  @residents [
               {Resident, [:register, :revise]},
               {ResidentIdentifier, [:add, :remove]},
               {Arrival, [:record, :correct]},
               {Departure, [:record, :correct, :withdraw]},
               {Absence, [:start, :finish]},
               {ParentLink, [:record, :remove]},
               {Family, [:name, :rename]},
               {FamilyMember, [:add, :remove]},
               {Group, [:form, :revise, :close]},
               {GroupMember, [:join, :leave]}
             ]
             |> Enum.flat_map(fn {resource, actions} ->
               Enum.map(actions, &{resource, &1, :all})
             end)

  @impl true
  def reads, do: for(resource <- @resources, do: {resource, :read, :all})

  @impl true
  def powers, do: %{residents: @residents, remove_residents: [{Resident, :remove, :all}]}
end
