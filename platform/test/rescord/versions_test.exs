defmodule Rescord.VersionsTest do
  @moduledoc """
  Reads the version resource of each resource of the lists and the residents.

  The version resource of a temporal resource reads the table of the
  resource. A fault in how AshPaperTrail builds it shows only when somebody
  reads the versions (ADR 0027), so this test reads each one.

  The test creates an organisation, so it does not run beside others (see
  `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  test "the versions of each resource can be read" do
    root = root!()
    organisation = organisation!(root)
    lists = lists!(organisation, root)
    resident!(lists, [actor: root, tenant: organisation], %{breed_ids: [lists.breed.rex]})

    resources =
      for domain <- [
            Rescord.Lists,
            Rescord.Residents,
            Rescord.Locations,
            Rescord.Journal,
            Rescord.Tasks,
            Rescord.Inventory
          ],
          resource <- Ash.Domain.Info.resources(domain),
          AshPaperTrail.Resource in Spark.extensions(resource) do
        resource
      end

    # 14 lists and 10 resources of the residents.
    assert length(resources) >= 24

    for resource <- resources do
      version = AshPaperTrail.Resource.Info.version_resource(resource)

      options =
        if Ash.Resource.Info.multitenancy_strategy(resource),
          do: [tenant: organisation, authorize?: false],
          else: [authorize?: false]

      assert is_list(Ash.read!(version, options)), "#{inspect(version)} cannot be read"
    end

    # The resident and its breed each have a version.
    resident_versions = AshPaperTrail.Resource.Info.version_resource(Rescord.Residents.Resident)
    assert [_one] = Ash.read!(resident_versions, tenant: organisation, authorize?: false)
  end
end
