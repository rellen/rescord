defmodule Rescord.TransfersTest do
  @moduledoc """
  Holds the partnerships and the transfers between refuges (ADR 0042): a
  question by short name and its answer, who sees what, the copy of a
  resident with the parts that the sender chooses, the answer of the
  refuge that receives it, and the power that each step needs.

  Each test creates organisations, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Journal, Transfers}

  setup do
    root = root!()
    wattle = organisation!(root, "Wattle Creek")
    banksia = organisation!(root, "Banksia Rise")
    {_, wattle_admin} = member!(wattle, :administrator, root)
    {_, wattle_member} = member!(wattle, :member, wattle_admin)
    {_, banksia_admin} = member!(banksia, :administrator, root)
    {_, banksia_member} = member!(banksia, :member, banksia_admin)
    lists = lists!(wattle, root)

    biscuit =
      resident!(lists, [actor: wattle_admin, tenant: wattle], %{markings: "Torn left ear"})

    {:ok,
     root: root,
     wattle: wattle,
     banksia: banksia,
     wattle_admin: wattle_admin,
     wattle_member: wattle_member,
     banksia_admin: banksia_admin,
     banksia_member: banksia_member,
     lists: lists,
     biscuit: biscuit}
  end

  defp partners!(context) do
    {:ok, asked} =
      Transfers.ask_partner(context.wattle, context.banksia.short_name,
        actor: context.wattle_admin
      )

    {:ok, accepted} = Transfers.accept_partner(asked, actor: context.banksia_admin)
    accepted
  end

  defp send!(context, extra \\ %{}) do
    %{
      organisation_id: context.wattle.id,
      partner_id: context.banksia.id,
      resident_id: context.biscuit.id
    }
    |> Map.merge(extra)
    |> Transfers.send_transfer(actor: context.wattle_admin)
  end

  describe "a partnership" do
    test "is asked by short name, and accepted by the other refuge", context do
      assert {:ok, asked} =
               Transfers.ask_partner(context.wattle, " #{context.banksia.short_name} ",
                 actor: context.wattle_admin
               )

      assert asked.state == :asked
      assert asked.asked_by_id == context.wattle_admin.id

      # The refuge that asked does not answer.
      assert {:error, %Ash.Error.Forbidden{}} =
               Transfers.accept_partner(asked, actor: context.wattle_admin)

      # A member there does not answer either.
      assert {:error, %Ash.Error.Forbidden{}} =
               Transfers.accept_partner(asked, actor: context.banksia_member)

      assert {:ok, %{state: :accepted, answered_by_id: by}} =
               Transfers.accept_partner(asked, actor: context.banksia_admin)

      assert by == context.banksia_admin.id

      assert {:ok, [{"Banksia Rise", id}]} =
               Transfers.partners_of(context.wattle, actor: context.wattle_member)

      assert id == context.banksia.id
    end

    test "names another refuge that exists, and one question at a time", context do
      for name <- ["no-such-refuge", context.wattle.short_name] do
        assert {:error, %Ash.Error.Invalid{} = error} =
                 Transfers.ask_partner(context.wattle, name, actor: context.wattle_admin)

        assert Accounts.error_messages(error) == ["Short name names no other refuge"]
      end

      partners!(context)

      # Not again, in either direction.
      assert {:error, %Ash.Error.Invalid{}} =
               Transfers.ask_partner(context.banksia, context.wattle.short_name,
                 actor: context.banksia_admin
               )
    end

    test "is asked by a person with the power, and seen by each member of the two", context do
      assert {:error, %Ash.Error.Forbidden{}} =
               Transfers.ask_partner(context.wattle, context.banksia.short_name,
                 actor: context.wattle_member
               )

      # A person of another refuge does not ask in the name of this one.
      assert {:error, %Ash.Error.Forbidden{}} =
               Transfers.ask_partner(context.wattle, context.banksia.short_name,
                 actor: context.banksia_admin
               )

      partnership = partners!(context)

      for actor <- [context.wattle_member, context.banksia_member] do
        assert {:ok, [%{id: id}]} = Transfers.partnerships(actor: actor)
        assert id == partnership.id
      end

      third = organisation!(context.root, "Third")
      {_, outsider} = member!(third, :administrator, context.root)
      assert {:ok, []} = Transfers.partnerships(actor: outsider)
      assert {:ok, []} = Transfers.partnerships(actor: nil)
    end

    test "ends, from either refuge, and is declined by the other", context do
      partnership = partners!(context)

      assert {:error, %Ash.Error.Forbidden{}} =
               Transfers.end_partnership(partnership, actor: context.banksia_member)

      assert {:ok, %{state: :ended}} =
               Transfers.end_partnership(partnership, actor: context.banksia_admin)

      {:ok, asked} =
        Transfers.ask_partner(context.banksia, context.wattle.short_name,
          actor: context.banksia_admin
        )

      assert {:ok, %{state: :declined}} =
               Transfers.decline_partner(asked, actor: context.wattle_admin)

      assert {:ok, []} = Transfers.partners_of(context.wattle, actor: context.wattle_admin)
    end
  end

  describe "a transfer" do
    setup context do
      Journal.write_entry!(
        %{
          resident_id: context.biscuit.id,
          kind: :measurement,
          measure_kind_id: context.lists.measure_kind.weight,
          value: "1095",
          unit_id: context.lists.unit.g
        },
        actor: context.wattle_admin,
        tenant: context.wattle
      )

      Journal.write_entry!(
        %{resident_id: context.biscuit.id, kind: :behaviour, note: "Popcorning at floor time."},
        actor: context.wattle_admin,
        tenant: context.wattle
      )

      :ok
    end

    test "needs a partner", context do
      assert {:error, %Ash.Error.Invalid{} = error} = send!(context)
      assert Accounts.error_messages(error) == ["Partner is not a partner refuge"]
    end

    test "holds the facts and the medical history, and the parts that the sender chooses",
         context do
      partners!(context)

      assert {:ok, plain} = send!(context)
      assert plain.state == :sent
      assert plain.parts == []
      assert plain.resident_name == "Biscuit"
      assert plain.snapshot["facts"]["name"] == "Biscuit"
      assert plain.snapshot["facts"]["markings"] == "Torn left ear"

      assert [%{"kind" => "measurement", "facts" => %{"value" => "1095", "unit" => "g"}}] =
               plain.snapshot["medical"]

      refute Map.has_key?(plain.snapshot, "journal")
      refute Map.has_key?(plain.snapshot, "stay")

      assert {:ok, full} = send!(context, %{parts: [:stay, :journal, :journal]})
      assert full.parts == [:journal, :stay]

      assert [%{"kind" => "behaviour", "note" => "Popcorning at floor time."}] =
               full.snapshot["journal"]

      assert %{"arrival" => %{"on" => _}} = full.snapshot["stay"]

      assert {:error, %Ash.Error.Invalid{}} = send!(context, %{parts: [:no_such_part]})
    end

    test "holds the conditions of the resident by name, and what each entry is about",
         context do
      partners!(context)
      options = [actor: context.wattle_admin, tenant: context.wattle]
      today = Accounts.today(context.wattle)

      assert {:ok, %{snapshot: %{"conditions" => []}}} = send!(context)

      Journal.write_entry!(
        %{
          resident_id: context.biscuit.id,
          kind: :diagnosis,
          condition_id: context.lists.condition.respiratory_infection,
          onset_on: Date.add(today, -6),
          chronic: true
        },
        options
      )

      {:ok, [episode]} = Journal.episodes_of(context.biscuit.id, options)
      {:ok, episode} = Journal.revise_episode(episode, %{note: "Sneezes at night"}, options)

      Journal.write_entry!(
        %{
          resident_id: context.biscuit.id,
          kind: :procedure,
          procedure_kind_id: context.lists.procedure_kind.desexing,
          episode_id: episode.id
        },
        options
      )

      {:ok, _resolved} =
        Journal.resolve_episode(episode, %{ended_on: Date.add(today, -1)}, options)

      assert {:ok, transfer} = send!(context)

      assert transfer.snapshot["conditions"] == [
               %{
                 "condition" => "Respiratory infection",
                 "started_on" => today |> Date.add(-6) |> Date.to_iso8601(),
                 "ended_on" => today |> Date.add(-1) |> Date.to_iso8601(),
                 "chronic" => true,
                 "note" => "Sneezes at night"
               }
             ]

      about = Map.new(transfer.snapshot["medical"], &{&1["kind"], &1["about"]})
      assert about["procedure"] == "Respiratory infection"
      assert about["diagnosis"] == "Respiratory infection"
      assert about["measurement"] == nil

      # The copy names no id of the refuge that sends it.
      refute inspect(transfer.snapshot["conditions"]) =~ episode.id
      refute inspect(transfer.snapshot["medical"]) =~ episode.id
    end

    test "does not change: a later change to the resident is not in the copy", context do
      partners!(context)
      {:ok, transfer} = send!(context)

      Rescord.Residents.revise_resident!(context.biscuit, %{name: "Biscuit the second"},
        actor: context.wattle_admin,
        tenant: context.wattle
      )

      {:ok, again} = Transfers.transfer_of(context.banksia, transfer.id, actor: context.root)
      assert again.snapshot["facts"]["name"] == "Biscuit"
    end

    test "appears at the other refuge for the power to answer, and for each member after",
         context do
      partners!(context)
      {:ok, transfer} = send!(context)

      # The member of the refuge that receives sees nothing yet.
      assert {:ok, nil} =
               Transfers.transfer_of(context.banksia, transfer.id, actor: context.banksia_member)

      assert {:ok, %{}} =
               Transfers.transfer_of(context.banksia, transfer.id, actor: context.banksia_admin)

      # Each member of the refuge that sent it sees it.
      assert {:ok, %{}} =
               Transfers.transfer_of(context.wattle, transfer.id, actor: context.wattle_member)

      assert {:error, %Ash.Error.Forbidden{}} =
               Transfers.accept_transfer(transfer, actor: context.banksia_member)

      assert {:error, %Ash.Error.Forbidden{}} =
               Transfers.accept_transfer(transfer, actor: context.wattle_admin)

      assert {:ok, %{state: :accepted}} =
               Transfers.accept_transfer(transfer, actor: context.banksia_admin)

      assert {:ok, %{snapshot: %{"facts" => %{"name" => "Biscuit"}}}} =
               Transfers.transfer_of(context.banksia, transfer.id, actor: context.banksia_member)

      third = organisation!(context.root, "Third")
      {_, outsider} = member!(third, :administrator, context.root)
      assert {:ok, []} = Transfers.transfers(actor: outsider)
    end

    test "is sent by a person with the power, of a resident of the refuge", context do
      partners!(context)

      assert {:error, %Ash.Error.Forbidden{}} =
               Transfers.send_transfer(
                 %{
                   organisation_id: context.wattle.id,
                   partner_id: context.banksia.id,
                   resident_id: context.biscuit.id
                 },
                 actor: context.wattle_member
               )

      assert {:error, %Ash.Error.Invalid{} = error} =
               send!(context, %{resident_id: Ash.UUID.generate()})

      assert Accounts.error_messages(error) == ["Resident is not a resident of this refuge"]
    end

    test "is withdrawn by the sender, or declined, while it waits", context do
      partners!(context)
      {:ok, first} = send!(context)
      {:ok, second} = send!(context)

      assert {:error, %Ash.Error.Forbidden{}} =
               Transfers.withdraw_transfer(first, actor: context.banksia_admin)

      assert {:ok, %{state: :withdrawn}} =
               Transfers.withdraw_transfer(first, actor: context.wattle_admin)

      assert {:ok, %{state: :declined}} =
               Transfers.decline_transfer(second, actor: context.banksia_admin)

      # An answer that comes after another one is stale.
      assert {:error, %Ash.Error.Invalid{}} =
               Transfers.accept_transfer(second, actor: context.banksia_admin)
    end
  end
end
