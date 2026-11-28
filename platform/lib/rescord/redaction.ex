defmodule Rescord.Redaction do
  @moduledoc """
  The one change of old versions (ADR 0105). The paper trail is never
  changed, and the version resources refuse every actor (ADR 0063), with
  one exception: an erasure on request replaces the personal fields of
  the versions of a person with the word "REDACTED".

  Only an erasure calls it: `Rescord.Privacy`, for the email of an
  account, and the change of the calendar feeds that hears
  `:member_erased`, for the name of a feed. `Rescord.RedactionTest` fails
  for any other caller in `lib/` (issue 31, call 17).

  It works on the version table of a resource that is not temporal, whose
  `changes` is a map (`change_tracking_mode :changes_only`). A field that
  a version does not hold stays out of it.
  """

  @doc """
  Replaces each of `fields` with "REDACTED" in the `changes` of each
  version of the records of `resource` whose ids are `ids`. `tenant` is the
  organisation for a resource in its schema, or `nil`. Returns the count of
  the versions that changed.
  """
  @spec redact_versions(module, [Ecto.UUID.t()], [atom], term) :: non_neg_integer
  def redact_versions(_resource, [], _fields, _tenant), do: 0
  def redact_versions(_resource, _ids, [], _tenant), do: 0

  def redact_versions(resource, ids, fields, tenant) do
    version = AshPaperTrail.Resource.Info.version_resource(resource)
    table = AshPostgres.DataLayer.Info.table(version)
    prefix = prefix(version, tenant)
    names = Enum.map(fields, &Atom.to_string/1)
    uuids = Enum.map(ids, &Ecto.UUID.dump!/1)

    # `jsonb_object_agg` puts the word in place of each named key that the
    # version holds, and keeps each other key.
    sql = """
    UPDATE #{quote_name(prefix)}.#{quote_name(table)}
    SET changes = changes || (
      SELECT jsonb_object_agg(key, to_jsonb('REDACTED'::text))
      FROM jsonb_object_keys(changes) AS key
      WHERE key = ANY($2)
    )
    WHERE version_source_id = ANY($1) AND changes ?| $2
    """

    %{num_rows: count} = Rescord.Repo.query!(sql, [uuids, names])
    count
  end

  defp prefix(version, nil),
    do: AshPostgres.DataLayer.Info.schema(version) || "public"

  defp prefix(_version, "org_" <> _ = schema), do: schema
  defp prefix(_version, tenant), do: Ash.ToTenant.to_tenant(tenant, nil)

  defp quote_name(name) do
    if Regex.match?(~r/\A[a-z_][a-z0-9_-]*\z/, name),
      do: ~s("#{name}"),
      else: raise(ArgumentError, "not a name of a table: #{inspect(name)}")
  end
end
