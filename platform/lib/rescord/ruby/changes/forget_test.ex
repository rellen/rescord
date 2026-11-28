defmodule Rescord.Ruby.Changes.ForgetTest do
  @moduledoc """
  Forgets what the last test of a provider found, when the action changes
  where a request goes or which model answers it: the model, the address
  or the region. The result of a test is about the settings that it ran
  with, so a page never says "Answered" for settings that nobody tested.
  """

  use Ash.Resource.Change

  @tested [:model, :base_url, :region]

  @impl true
  def change(changeset, _opts, _context) do
    if Enum.any?(@tested, &Ash.Changeset.changing_attribute?(changeset, &1)) do
      changeset
      |> Ash.Changeset.force_change_attribute(:tested_at, nil)
      |> Ash.Changeset.force_change_attribute(:test_result, nil)
    else
      changeset
    end
  end
end
