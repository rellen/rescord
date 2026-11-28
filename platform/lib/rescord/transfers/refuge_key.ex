defmodule Rescord.Transfers.RefugeKey do
  @moduledoc """
  The keys of a refuge for the transfer files between servers (ADR 0043):
  the public key that signs and the public key that receives, and the two
  private keys, which `Rescord.Transfers.Crypto.wrap/2` encrypts with the
  secret of the server.

  `Rescord.Transfers.Keys` makes the record the first time that a refuge
  needs it, and is the only reader: no policy lets a person read or change
  it, and a root user does not need to.
  """

  use Rescord.Resource,
    domain: Rescord.Transfers,
    shared?: true,
    temporal?: false,
    archive?: false,
    paper_trail?: false,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "refuge_keys"
  end

  actions do
    defaults [:read]

    create :make do
      accept [:organisation_id, :sign_public, :box_public, :sign_private, :box_private]
    end

    update :rewrap do
      description "Keeps the private keys under the new secret of the server (ADR 0068)"
      accept [:sign_private, :box_private]
    end
  end

  # No policy: each request through a policy is refused, and the keys are
  # read with `authorize?: false` by `Rescord.Transfers.Keys` alone.
  policies do
    policy always() do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :organisation_id, :uuid, allow_nil?: false, public?: true
    attribute :sign_public, :binary, allow_nil?: false, public?: true
    attribute :box_public, :binary, allow_nil?: false, public?: true

    attribute :sign_private, :binary do
      allow_nil? false
      sensitive? true
      description "The private key that signs, encrypted with the secret of the server"
    end

    attribute :box_private, :binary do
      allow_nil? false
      sensitive? true
      description "The private key that receives, encrypted with the secret of the server"
    end

    create_timestamp :inserted_at
  end

  identities do
    identity :one_for_each_refuge, [:organisation_id]
  end
end
