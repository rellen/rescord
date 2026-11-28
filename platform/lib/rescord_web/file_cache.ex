defmodule RescordWeb.FileCache do
  @moduledoc """
  How long a browser keeps a file that Rescord sends (issue 34, ADR 0112).

  A photo, its thumbnail and its display file, a journal file and a
  receipt have bytes that never change for their address: a record names
  its files once, and a new file is a new record. So the browser of the
  person keeps such a file for a week (`kept/0`), and a page that shows the
  same thumbnails again reads none of them from the server. `private`
  keeps the copy out of each shared cache: only that browser keeps it. The
  read with the grants of the person still decides who gets the file the
  first time.

  A copy in a browser outlives a grant: a person who leaves the
  organisation, or the removal of a photo, does not take it from a browser
  that has it. So the sign-out sends `Clear-Site-Data: "cache"`
  (`RescordWeb.UserAuth.sign_out/1`), which clears the copies of the
  server where the browser supports the header.

  Each other answer keeps `private, no-store` (`none/0`): a journal photo
  that Rescord 0.1.0 kept as it was sent, whose bytes change when the job of
  the images cleans it (ADR 0109); the files of a transfer, of which a copy
  from 0.1.0 can hold such a photo; the reports, the exports and the pages.
  """

  import Plug.Conn

  @kept "private, max-age=604800, immutable"
  @none "private, no-store"

  @doc "The `cache-control` of a file whose bytes never change: a week, in the browser alone."
  @spec kept() :: String.t()
  def kept, do: @kept

  @doc "The `cache-control` of each other file: no copy anywhere."
  @spec none() :: String.t()
  def none, do: @none

  @doc "Puts `kept/0` on the answer when `kept?` is true, and `none/0` when it is not."
  @spec put(Plug.Conn.t(), boolean) :: Plug.Conn.t()
  def put(conn, kept?) when is_boolean(kept?),
    do: put_resp_header(conn, "cache-control", if(kept?, do: @kept, else: @none))

  @doc """
  Whether the file of a photo record or of a journal attachment keeps its
  bytes: each one does but an image with no thumbnail, which the job of the
  images writes again (ADR 0109).
  """
  @spec stable?(map) :: boolean
  def stable?(%{content_type: "image/" <> _, thumbnail_key: nil}), do: false
  def stable?(%{}), do: true
end
