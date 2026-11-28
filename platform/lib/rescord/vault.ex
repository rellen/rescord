defmodule Rescord.Vault do
  @moduledoc """
  The one vault of Rescord (ADR 0068). AshCloak encrypts each secret
  attribute of a settings resource with it, through `encrypt!/1` and
  `decrypt!/1`. It is a plain module over `:crypto`, with no process and no
  package.

  The cipher is AES-256-GCM, with a new nonce of 12 bytes for each value.
  The key comes from the secret of the server (`RESCORD_KEY_SECRET`)
  through HMAC-SHA256 with a label. The label gives the vault a key that
  the transfers do not use (`Rescord.Transfers.Crypto.wrap/2` has another
  label).

  A value starts with a version byte and the id of its key, 4 bytes of a
  hash of the key. So the server reads the values of two secrets while its
  secret changes: `config :rescord, Rescord.Vault` holds `secret:`, and
  `previous_secret:` for the time of the change. `encrypt!/1` writes with
  the first. `rotate/0` writes each value of the old secret again, and
  `bin/rotate-vault` runs it.

  The secret is the one value that cannot be in the database: it opens
  what the database holds.
  """

  use Boundary, top_level?: true, deps: [Rescord], exports: [Sealed]

  import Ecto.Query

  alias Rescord.Repo

  defmodule Sealed do
    @moduledoc "A value that this caller may not open, or that this server cannot open."
    use Splode.Error, fields: [:field], class: :forbidden

    def message(_error), do: "this value cannot be opened"
  end

  @label "rescord vault 1"
  @version 1

  @typedoc "What `rotate/0` and `count/0` found, as numbers of values."
  @type report :: %{current: non_neg_integer, previous: non_neg_integer, sealed: non_neg_integer}

  @doc "Encrypts with the secret of the server."
  @spec encrypt!(binary) :: binary
  def encrypt!(plaintext) when is_binary(plaintext) do
    [{id, key} | _previous] = keys()
    nonce = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, plaintext, @label, true)

    <<@version, id::binary, nonce::binary, tag::binary, ciphertext::binary>>
  end

  @doc """
  Decrypts, or raises `Rescord.Vault.Sealed`: no secret of this server
  made the value, or somebody changed it.
  """
  @spec decrypt!(binary) :: binary
  def decrypt!(
        <<@version, id::binary-size(4), nonce::binary-size(12), tag::binary-size(16),
          ciphertext::binary>>
      ) do
    with {^id, key} <- List.keyfind(keys(), id, 0),
         plaintext when is_binary(plaintext) <-
           :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, ciphertext, @label, tag, false) do
      plaintext
    else
      _refused -> raise Sealed
    end
  end

  def decrypt!(_other), do: raise(Sealed)

  @doc "Whether the secret of today wrote this value."
  @spec current?(binary) :: boolean
  def current?(<<@version, id::binary-size(4), _rest::binary>>),
    do: match?([{^id, _key} | _previous], keys())

  def current?(_other), do: false

  @doc """
  The resources with a secret in this vault: each resource of each domain
  with the extension AshCloak. Nothing names them here, so no list can miss
  one.
  """
  @spec resources() :: [module]
  def resources do
    for domain <- Application.fetch_env!(:rescord, :ash_domains),
        resource <- Ash.Domain.Info.resources(domain),
        AshCloak in Spark.extensions(resource),
        do: resource
  end

  @doc """
  Counts the values of the vault: those that the secret of today wrote,
  those of the previous secret, and those that no secret of this server
  opens. It changes nothing. `bin/check` shows it.
  """
  @spec count() :: report
  def count, do: visit(false)

  @doc """
  Writes each value of the previous secret again with the secret of today,
  and returns the counts as they were before. A value that no secret opens
  stays as it is. A second run changes nothing.

  It writes the column and nothing else: no action runs, and the paper
  trail gets no version. The paper trail of a resource with a secret leaves
  the encrypted attribute out in each case (ADR 0068).
  """
  @spec rotate() :: report
  def rotate, do: visit(true)

  # Visits each encrypted value of each resource, and with `write?` writes
  # each value of the previous secret again.
  defp visit(write?) do
    empty = %{current: 0, previous: 0, sealed: 0}

    for resource <- resources(),
        prefix <- prefixes(resource),
        column <- columns(resource),
        reduce: empty do
      report -> visit_column(resource, prefix, column, write?, report)
    end
  end

  defp visit_column(resource, prefix, column, write?, report) do
    table = AshPostgres.DataLayer.Info.table(resource)
    [key] = Ash.Resource.Info.primary_key(resource)

    rows =
      from(row in table,
        where: not is_nil(field(row, ^column)),
        select: {field(row, ^key), field(row, ^column)}
      )
      |> Repo.all(prefix: prefix)

    Enum.reduce(rows, report, fn {id, stored}, report ->
      kind = kind(stored)

      if write? and kind == :previous do
        again = stored |> Base.decode64!() |> decrypt!() |> encrypt!() |> Base.encode64()

        from(row in table, where: field(row, ^key) == ^id)
        |> Repo.update_all([set: [{column, again}]], prefix: prefix)
      end

      Map.update!(report, kind, &(&1 + 1))
    end)
  end

  defp kind(stored) do
    # AshCloak keeps the value of the vault as Base64 in the column.
    with {:ok, value} <- Base.decode64(stored),
         _plaintext <- decrypt!(value) do
      if current?(value), do: :current, else: :previous
    else
      :error -> :sealed
    end
  rescue
    Sealed -> :sealed
  end

  defp columns(resource) do
    for attribute <- AshCloak.Info.cloak_attributes!(resource),
        do: String.to_existing_atom("encrypted_#{attribute}")
  end

  # A resource of an organisation has a table in each schema.
  defp prefixes(resource) do
    case Ash.Resource.Info.multitenancy_strategy(resource) do
      :context -> Repo.all_tenants()
      _shared -> [AshPostgres.DataLayer.Info.schema(resource)]
    end
  end

  # The secret of today first: it encrypts. Each secret decrypts its own
  # values. The id is a hash of the key, so it does not help to find it.
  defp keys do
    config = Application.fetch_env!(:rescord, __MODULE__)

    for secret <- [config[:secret], config[:previous_secret]], is_binary(secret) do
      key = :crypto.mac(:hmac, :sha256, secret, @label)
      {binary_part(:crypto.hash(:sha256, "id" <> key), 0, 4), key}
    end
  end
end
