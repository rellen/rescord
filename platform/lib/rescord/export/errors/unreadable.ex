defmodule Rescord.Export.Errors.Unreadable do
  @moduledoc """
  A table that the export could not read (ADR 0077, E2). It names the file
  of the table in the export, such as `residents.csv`, and not the error of
  the read: the message of that error can hold a value of a record. The log
  has the kind of that error.

  It is a fault of the server, and not of the person who asked, so its
  class is `:unknown`.
  """

  use Splode.Error, fields: [:file], class: :unknown

  @impl true
  def message(%{file: file}), do: "The export could not read #{file}."
end
