defmodule Rescord.ExportTest do
  @moduledoc """
  Holds the export of the data of an organisation (ADR 0054): a ZIP with a
  README and a CSV file for each table, the data as it stood at the end of
  the chosen day, the data of the organisation alone, the power `export`,
  and each resource of the domains either in the export or left out with a
  reason.

  Each test creates organisations, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Export, Lists, Residents}

  setup do
    root = root!()
    wattle = organisation!(root, "Wattle Creek")
    banksia = organisation!(root, "Banksia Rise")
    {_, administrator} = member!(wattle, :administrator, root)
    {_, member} = member!(wattle, :member, administrator)

    # The species exists from four days ago, Biscuit from three days ago, and
    # the name Bis from now. A temporal record names a value that exists at
    # its own instant.
    now = DateTime.utc_now()
    options = [actor: administrator, tenant: wattle]

    {:ok, species} =
      Lists.add_local_value(:species, "Guinea pig",
        actor: root,
        tenant: wattle,
        as_of: DateTime.add(now, -4, :day)
      )

    biscuit =
      Residents.register_resident!(
        %{
          name: "Biscuit",
          species_id: species.id,
          sex: :male,
          arrival_kind: :surrender,
          arrived_on: Date.add(Accounts.today(wattle), -3)
        },
        [as_of: DateTime.add(now, -3, :day)] ++ options
      )

    {:ok, _} = Residents.revise_resident(biscuit, %{name: "Bis"}, options)

    banksia_lists = lists!(banksia, root)
    resident!(banksia_lists, [actor: root, tenant: banksia], %{name: "Pepper"})

    {:ok,
     root: root,
     wattle: wattle,
     administrator: administrator,
     member: member,
     today: Accounts.today(wattle)}
  end

  # The files of a ZIP of the export, by their names in its folder.
  defp files(%{zip: zip}) do
    {:ok, entries} = :zip.unzip(zip, [:memory])
    Map.new(entries, fn {name, bytes} -> {name |> to_string() |> Path.basename(), bytes} end)
  end

  test "an administrator gets a ZIP with a README and a CSV file for each table", context do
    assert {:ok, export} =
             Export.export(context.wattle, context.today, actor: context.administrator)

    assert export.filename == "rescord-#{context.wattle.short_name}-#{context.today}.zip"
    files = files(export)

    assert Map.keys(files) |> Enum.sort() ==
             Enum.sort(["README.txt" | Enum.map(Export.resources(), &Export.file/1)])

    assert "﻿id,name,short_name" <> _ = files["organisation.csv"]
    assert files["organisation.csv"] =~ "Wattle Creek"
    assert files["resident_names.csv"] =~ ",Bis,"
    assert files["members.csv"] =~ to_string(context.administrator.email)
    assert files["residents.csv"] =~ "male"
    assert files["base_species.csv"] =~ "id,name"
  end

  test "a table is as it stood at the end of the chosen day", context do
    two_days_ago = Date.add(context.today, -2)

    assert {:ok, export} =
             Export.export(context.wattle, two_days_ago, actor: context.administrator)

    names = files(export)["resident_names.csv"]

    assert names =~ "Biscuit"
    refute names =~ ",Bis,"

    # Before the arrival, there was no resident.
    long_ago = Date.add(context.today, -30)
    assert {:ok, export} = Export.export(context.wattle, long_ago, actor: context.administrator)

    assert files(export)["residents.csv"] ==
             "﻿id,sex,born_on,born_on_estimated,species_id,size_class_id,coat_id\r\n"
  end

  test "holds the data of its own organisation alone", context do
    assert {:ok, export} =
             Export.export(context.wattle, context.today, actor: context.administrator)

    for {_file, bytes} <- files(export) do
      refute bytes =~ "Pepper"
      refute bytes =~ "Banksia Rise"
    end
  end

  test "needs the power export, which a member does not have and a root user does", context do
    assert Export.export(context.wattle, context.today, actor: context.member) ==
             {:error, :forbidden}

    assert Export.export(context.wattle, context.today, actor: user!()) == {:error, :forbidden}
    assert {:ok, _export} = Export.export(context.wattle, context.today, actor: context.root)

    role = fn user ->
      {:ok, _organisation, member} = Accounts.organisation_for(user, context.wattle.short_name)
      Accounts.role_in(user, member)
    end

    refute Accounts.role_can_export?(role.(context.member))
    assert Accounts.role_can_export?(role.(context.administrator))
  end

  test "refuses a date after today", context do
    assert Export.export(context.wattle, Date.add(context.today, 1), actor: context.administrator) ==
             {:error, "The date is after today."}

    assert Export.export(context.wattle, "2026-11-25", actor: context.administrator) ==
             {:error, "The date is not a date."}
  end

  test "the README says when, and which file each id names", context do
    assert {:ok, export} =
             Export.export(context.wattle, context.today, actor: context.administrator)

    readme = files(export)["README.txt"]

    assert readme =~ "The data of Wattle Creek in Rescord"
    assert readme =~ "As of: the end of #{context.today} in Australia/Brisbane"
    assert readme =~ "- resident_names.csv: resident_id names a row of residents.csv"
    assert readme =~ "- tasks.csv ("
    assert readme =~ "journal_attachments.csv lists"

    # The files that keep no history are in the second list.
    [_history, present] = String.split(readme, "These files keep no history", parts: 2)
    assert present =~ "- tasks.csv ("
    refute present =~ "- resident_names.csv ("
  end

  test "each resource of the domains is in the export, or left out with a reason" do
    domains = Application.fetch_env!(:rescord, :ash_domains)

    resources =
      for domain <- domains,
          resource <- Ash.Domain.Info.resources(domain),
          not Export.version?(resource),
          do: resource

    exported = MapSet.new(Export.resources())
    excluded = MapSet.new(Map.keys(Export.excluded()))

    assert length(resources) > 60, "the domains hold #{length(resources)} resources"

    for resource <- resources do
      assert MapSet.member?(exported, resource) != MapSet.member?(excluded, resource),
             "#{inspect(resource)} must be in the export or in Export.excluded/0, and not both"
    end

    # Two resources never share a file.
    files = Enum.map(Export.resources(), &Export.file/1)
    assert files == Enum.uniq(files)
  end
end
