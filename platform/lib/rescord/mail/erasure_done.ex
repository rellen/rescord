defmodule Rescord.Mail.ErasureDone do
  @moduledoc """
  The email that tells a person that an organisation erased their data
  (ADR 0105): `erasure_done.mjml.eex`, and its text part.
  """

  use MjmlEEx,
    mjml_template: "erasure_done.mjml.eex",
    layout: Rescord.Mail.Layout,
    mode: :compile

  @doc "The text part."
  @spec text(map) :: String.t()
  def text(%{organisation: organisation, label: label, kept: kept, note: note}) do
    """
    #{organisation} erased your data in Rescord, as you asked. Your email address is gone from its records, and they name you "#{label}".

    #{kept}

    The records that members wrote about the animals stay, because the care of each animal depends on them. The backups of the server hold your data until they are deleted, and nobody uses them for anything else.

    #{note}
    """
  end
end
