defmodule RescordWeb.Input do
  @moduledoc """
  What a page draws again from the fields of a form that the browser sent.

  A page that refuses a form draws it again with what the person typed. A
  forged event can send a list or a map where the form sends text, and a
  form cannot draw a map as the value of a field: the page would stop. So a
  page draws the typed fields again with `typed_form/2`, which keeps only
  text, and lists of text for a field with several values.

  Each LiveView imports `typed_form/2` and `Shoddy.Maps.text_fields/1`
  (`use RescordWeb, :live_view`). `text_fields/1` gives the fields that
  `typed_form/2` keeps, for a page that reads them itself. A page reads one
  field with `Shoddy.Strings.non_blank/1`.

  A page that an action refused passes the error as `error:`, and each
  message of the error that names a field is shown at that field, with
  `aria-invalid` (ADR 0111). `Rescord.Accounts.error_messages/1` still gives
  the whole list for the problems of the page.
  """

  @doc """
  A form of `Phoenix.Component.to_form/2` with the fields that
  `Shoddy.Maps.text_fields/1` keeps.

      iex> form = RescordWeb.Input.typed_form(%{"name" => "Fern", "note" => %{"a" => 1}}, as: :resident)
      iex> form.params
      %{"name" => "Fern"}

      iex> RescordWeb.Input.typed_form(["a list"], as: :resident).params
      %{}
  """
  @spec typed_form(term, keyword) :: Phoenix.HTML.Form.t()
  def typed_form(fields, opts) do
    {error, opts} = Keyword.pop(opts, :error)

    errors =
      for {field, message} <- Rescord.Accounts.field_errors(error), do: {field, {message, []}}

    Phoenix.Component.to_form(Shoddy.Maps.text_fields(fields), Keyword.put(opts, :errors, errors))
  end
end
