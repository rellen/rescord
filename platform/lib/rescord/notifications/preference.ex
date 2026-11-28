defmodule Rescord.Notifications.Preference do
  @moduledoc """
  On which channels one member gets one kind of notification in the
  organisation (issue 29, section 11). With no row, the member gets each
  kind on each channel that they set up: a device of Web Push, a topic of
  ntfy. The page of notifications writes a row for each kind.

  A notification is always in the app: the app is no channel here.
  """

  use Rescord.Resource,
    domain: Rescord.Notifications,
    temporal?: false,
    archive?: false,
    paper_trail?: false,
    authorizers: [Ash.Policy.Authorizer]

  @type t :: %__MODULE__{}

  postgres do
    table "notification_preferences"
  end

  actions do
    defaults [:read]

    create :set do
      description "The channels of one kind of notification of the actor"
      accept [:kind, :channels]
      upsert? true
      upsert_identity :one_kind
      upsert_fields [:channels]
      change Rescord.Notifications.Changes.SetUser
    end
  end

  # A preference is of one person: no bypass for a root user.
  policies do
    policy always() do
      authorize_if Rescord.Accounts.Checks.Granted
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
      public? true
      writable? false
    end

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:told, :comment]
    end

    attribute :channels, {:array, :atom} do
      allow_nil? false
      default []
      public? true
      constraints items: [one_of: [:web_push, :ntfy]]
    end
  end

  identities do
    identity :one_kind, [:user_id, :kind]
  end
end
