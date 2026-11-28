defmodule Rescord.Ruby.Validations.RubyOn do
  @moduledoc """
  Holds that Ruby is on in this organisation for the person who says a
  thing (`Rescord.Ruby.available?/2`): the settings, the provider, the
  place that an administrator agreed to, and the power `ruby` of the role.
  It reads the database, and decrypts no key.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, context) do
    if Rescord.Ruby.available?(context.actor, changeset.tenant),
      do: :ok,
      else: {:error, field: :text, message: "Ruby is off here"}
  end
end
