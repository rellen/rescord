defmodule Rescord.Notifications.Changes.MakeKeys do
  @moduledoc """
  Makes a new key pair of Web Push for the server: the public key in the
  clear, the private key encrypted with AshCloak. No page and no log gets
  the private key.
  """

  use Ash.Resource.Change

  alias Rescord.Notifications.WebPush

  @impl true
  def change(changeset, _opts, _context) do
    %{public: public, private: private} = WebPush.keys()

    changeset
    |> Ash.Changeset.force_change_attribute(:vapid_public_key, WebPush.encode(public))
    |> Ash.Changeset.force_change_attribute(:keys_made_at, DateTime.utc_now())
    |> AshCloak.encrypt_and_set(:vapid_private_key, WebPush.encode(private))
  end
end
