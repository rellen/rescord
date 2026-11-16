defmodule RescordWeb.Input do
  @moduledoc """
  What a page draws again from the fields of a form that the browser sent.

  A page that refuses a form draws it again with what the person typed. A
  forged event can send a list or a map where the form sends text, and a
  form cannot draw a map as the value of a field: the page would stop. So a
  page draws the typed fields again with `typed_form/2`, which keeps only
  text, and lists of text for a field with several values.

  Each LiveView imports `typed_form/2` and `typed_fields/1`
  (`use RescordWeb, :live_view`). A page reads one field with
  `Shoddy.Strings.non_blank/1`.
  """

  @doc """
  The fields of a form that are text, or a list of text. Each other field
  goes, and each value of a list that is not text goes.

      iex> RescordWeb.Input.typed_fields(%{"name" => "Fern", "note" => %{"a" => 1}, "days" => ["1", %{}]})
      %{"name" => "Fern", "days" => ["1"]}

      iex> RescordWeb.Input.typed_fields(["a list"])
      %{}
  """
  @spec typed_fields(term) :: %{String.t() => String.t() | [String.t()]}
  def typed_fields(fields) when is_map(fields) do
    for {key, value} <- fields, is_binary(key), typed = typed(value), into: %{}, do: {key, typed}
  end

  def typed_fields(_other), do: %{}

  @doc "A form of `Phoenix.Component.to_form/2` with the fields that `typed_fields/1` keeps."
  @spec typed_form(term, keyword) :: Phoenix.HTML.Form.t()
  def typed_form(fields, opts), do: Phoenix.Component.to_form(typed_fields(fields), opts)

  defp typed(value) when is_binary(value), do: value
  defp typed(values) when is_list(values), do: Enum.filter(values, &is_binary/1)
  defp typed(_other), do: nil
end
