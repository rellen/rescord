defmodule Rescord.Health.Checks.OldJournalPhotos do
  @moduledoc """
  C16 of issue 38: journal photos of Rescord 0.1.0 that still carry the
  metadata that they were sent with, their EXIF and their GPS position
  (issue 34): an image with no thumbnail. The job of the images
  (`Rescord.Images.Workers.Complete`) cleans them each hour, so a count
  that stays says that it cannot.

  A note until the count is 0. The ids are those of the attachments.
  """

  use Rescord.Health.Check

  @impl true
  def name, do: :old_journal_photos
  @impl true
  def scope, do: :organisation
  @impl true
  def cadence, do: :daily
  @impl true
  def title, do: "Journal photos that still carry their metadata"

  @impl true
  def explain,
    do:
      "Photos from Rescord 0.1.0 keep the position where they were taken until the job of the " <>
        "images cleans them. A count that does not go down from day to day is in the warnings " <>
        "of the log of that job."

  @impl true
  def run(context) do
    """
    select a.id from #{table(context, "journal_attachments")} a
    where a.content_type like 'image/%' and a.thumbnail_key is null
    """
    |> query()
    |> found(:note)
  end
end
