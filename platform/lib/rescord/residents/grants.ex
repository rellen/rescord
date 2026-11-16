defmodule Rescord.Residents.Grants do
  @moduledoc """
  What a role can do with the residents of an organisation (ADR 0024).

  The care of the residents is the work of each member, so a member has each
  grant of an administrator but one: only an administrator removes a
  resident that was recorded by mistake. A role reads each fact. It writes
  the name, the desex status and the ties only through the resident.
  """

  @behaviour Rescord.Accounts.Grants

  alias Rescord.Residents.{
    Absence,
    Arrival,
    Departure,
    Resident,
    ResidentBreed,
    ResidentColour,
    ResidentDesexStatus,
    ResidentIdentifier,
    ResidentName,
    ResidentTemperament
  }

  @grants [
            {Resident, [:read, :register, :revise]},
            {ResidentName, [:read]},
            {ResidentDesexStatus, [:read]},
            {ResidentBreed, [:read]},
            {ResidentColour, [:read]},
            {ResidentTemperament, [:read]},
            {ResidentIdentifier, [:read, :add, :remove]},
            {Arrival, [:read, :record, :correct]},
            {Departure, [:read, :record, :correct, :withdraw]},
            {Absence, [:read, :start, :finish]}
          ]
          |> Enum.flat_map(fn {resource, actions} ->
            Enum.map(actions, &{resource, &1, :all})
          end)

  @impl true
  def grants, do: %{administrator: [{Resident, :remove, :all} | @grants], member: @grants}
end
