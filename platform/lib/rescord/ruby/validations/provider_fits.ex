defmodule Rescord.Ruby.Validations.ProviderFits do
  @moduledoc """
  Holds a provider to the rules of `Rescord.Ruby.LLM.Profile.problems/1`,
  and puts each problem on its field, so that the page says it there: a
  hosted service needs a key, Ollama takes none, a key goes only to an
  address with TLS, the limit of an answer is below the limit of a request.

  It reads the values as the action will leave them, and the key as the
  argument that AshCloak has not yet encrypted. It decrypts nothing: a
  stored key counts through `key_set_at`.
  """

  use Ash.Resource.Validation

  alias Rescord.Ruby.LLM.Profile

  @fields [
    :kind,
    :model,
    :base_url,
    :region,
    :effort,
    :max_output_tokens,
    :context_tokens,
    :price_input,
    :price_output,
    :key_set_at
  ]

  @impl true
  def validate(changeset, _opts, _context) do
    values =
      @fields
      |> Map.new(&{&1, Ash.Changeset.get_attribute(changeset, &1)})
      |> Map.put(:api_key, Ash.Changeset.get_argument(changeset, :api_key))

    case Profile.problems(values) do
      [] ->
        :ok

      problems ->
        {:error,
         for {field, words} <- problems do
           Ash.Error.Changes.InvalidAttribute.exception(field: field, message: words)
         end}
    end
  end
end
