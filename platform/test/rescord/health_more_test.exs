defmodule Rescord.HealthMoreTest do
  @moduledoc """
  The second build of the sanity checks (ADR 0114, issue 38, C13 to C23):
  the store against the records, keys of another organisation, old
  journal photos, residents who left and are still in care, two tasks for
  one time, history with no ids, usage counts that are not sent,
  notifications, transfers and backups. Each test makes the fault that a
  check finds with SQL or with the store, as no action makes it.

  Each test creates an organisation, so the tests do not run beside others.
  """

  use Rescord.DataCase, async: false
  use Oban.Testing, repo: Rescord.Repo

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.StorageFixtures

  alias Rescord.{Accounts, Comments, Health, Journal, Photos, Repo, Residents, Tasks, Transfers}
  alias Rescord.Health.Checks

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    disk_store!(Path.join(tmp_dir, "store"))
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    options = [actor: administrator, tenant: organisation]

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     lists: lists,
     options: options,
     today: Accounts.today(organisation),
     biscuit: resident!(lists, options),
     schema: "org_" <> organisation.id}
  end

  defp check(check, context, now \\ DateTime.utc_now()) do
    organisation = if check.scope() == :organisation, do: Accounts.organisation_of(context.schema)
    prefix = organisation && "org_" <> organisation.id

    assert {:ok, finding, _ms} =
             Health.run(check, %{now: now, organisation: organisation, prefix: prefix})

    finding
  end

  defp sql!(context, sql, params) do
    Repo.query!(String.replace(sql, "@", ~s("#{context.schema}".)), params)
  end

  defp uuid(id), do: Ecto.UUID.dump!(id)

  defp photo!(context),
    do: Photos.add_photo!(%{resident_id: context.biscuit.id, content: photo()}, context.options)

  describe "C13 and C15: the store against the records" do
    test "passes, then finds a missing file, a size that differs, and a leftover", context do
      photo = photo!(context)
      assert %{level: :ok} = check(Checks.StoreFiles, context)

      root = Application.fetch_env!(:rescord, Rescord.Storage.Disk)[:root]
      path = Path.join(root, photo.key)

      original = File.read!(path)

      # A file of another size under the key of the record.
      File.write!(path, "a short file")
      assert %{level: :fail, ids: [found]} = check(Checks.StoreFiles, context)
      assert found == photo.id

      # The file is gone.
      File.rm!(path)
      assert %{level: :fail, ids: [^found]} = check(Checks.StoreFiles, context)

      # Back, and a file that no record names.
      File.write!(path, original)
      leftover = Path.join([root, context.organisation.id, "photos", Ecto.UUID.generate()])
      File.write!(leftover, "nobody names me")
      assert %{level: :note, count: 1} = check(Checks.StoreFiles, context)
    end

    test "reads the domains that bin/check-files reads, in a job of its own" do
      assert Checks.StoreFiles.domains() == Rescord.Release.Files.domains()
      assert Health.own_job?(Checks.StoreFiles)
      refute Health.own_job?(Checks.Clock)

      File.mkdir_p!(Application.fetch_env!(:rescord, Rescord.Storage.Disk)[:root])
      Health.run_due()
      assert [job] = all_enqueued(worker: Rescord.Health.Workers.Check)
      assert job.args == %{"check" => "store_files"}
      refute Enum.any?(Health.results(actor: root!()), &(&1.check == :store_files))

      assert :ok = Rescord.Health.Workers.Check.perform(job)

      assert Enum.any?(
               Health.results(actor: root!()),
               &(&1.check == :store_files and &1.level == :ok)
             )
    end
  end

  test "C14: a key of another organisation", context do
    photo = photo!(context)
    assert %{level: :ok} = check(Checks.FileKeys, context)

    sql!(context, "update @photos set thumbnail_key = $1 where id = $2", [
      Ecto.UUID.generate() <> "/photos/" <> Ecto.UUID.generate(),
      uuid(photo.id)
    ])

    assert %{level: :fail, ids: [found]} = check(Checks.FileKeys, context)
    assert found == photo.id
  end

  test "C16: a journal photo with its metadata", context do
    {:ok, entry} =
      Journal.write_entry_with_files(
        %{resident_id: context.biscuit.id, kind: :general, note: "In the garden."},
        [{"garden.jpg", photo()}],
        context.options
      )

    assert %{level: :ok} = check(Checks.OldJournalPhotos, context)

    # As Rescord 0.1.0 kept it.
    sql!(context, "update @journal_attachments set thumbnail_key = null where entry_id = $1", [
      uuid(entry.id)
    ])

    assert %{level: :note, count: 1} = check(Checks.OldJournalPhotos, context)
  end

  describe "C17: a resident who left and is still in care" do
    test "named by a routine after the departure", context do
      routine =
        Tasks.start_routine!(
          %{
            title: "Hay",
            pattern: :daily,
            times: [~T[08:00:00]],
            starts_on: context.today,
            resident_ids: [context.biscuit.id]
          },
          context.options
        )

      Residents.record_departure!(
        %{resident_id: context.biscuit.id, kind: :release, departed_on: context.today},
        context.options
      )

      # The departure took the resident out of the routine and its tasks.
      assert %{level: :ok} = check(Checks.DepartedInCare, context)

      sql!(context, "update @routines set resident_ids = array[$1::uuid] where id = $2", [
        uuid(context.biscuit.id),
        uuid(routine.id)
      ])

      assert %{level: :fail, ids: [found]} = check(Checks.DepartedInCare, context)
      assert found == context.biscuit.id

      # The first page shows the resident to a role that records a departure.
      {:ok, _org, admin_member} =
        Accounts.organisation_for(context.administrator, context.organisation.short_name)

      role = Accounts.role_in(context.administrator, admin_member)

      assert {:ok, %{rows: rows}} = Health.attention(role, context.options)
      assert [%{kind: :departed_in_care, record: %{name: "Biscuit"}}] = rows
    end
  end

  test "C18: two tasks of a routine for one time", context do
    routine =
      Tasks.start_routine!(
        %{title: "Hay", pattern: :daily, times: [~T[08:00:00]], starts_on: context.today},
        context.options
      )

    {:ok, tasks} = Tasks.tasks(context.options)

    [first, second | _rest] =
      tasks |> Enum.filter(&(&1.routine_id == routine.id)) |> Enum.sort_by(& &1.due_at, DateTime)

    assert %{level: :ok} = check(Checks.DuplicateTasks, context)

    sql!(context, "update @tasks set due_at = $1 where id = $2", [
      DateTime.to_naive(first.due_at),
      uuid(second.id)
    ])

    assert %{level: :fail, count: 2} = check(Checks.DuplicateTasks, context)

    # A cancelled task keeps its time, and is no second task.
    Tasks.cancel_task!(second, context.options)
    assert %{level: :ok} = check(Checks.DuplicateTasks, context)
  end

  test "C19: a version of the last day with no ids", context do
    assert %{level: :ok} = check(Checks.VersionIds, context)

    # A temporal table holds its versions in its rows.
    sql!(context, "update @residents set correlation_id = null where id = $1", [
      uuid(context.biscuit.id)
    ])

    assert %{level: :note, count: count} = check(Checks.VersionIds, context)
    assert count >= 1

    # Ten days on, the row is too old to say.
    assert %{level: :ok} =
             check(Checks.VersionIds, context, DateTime.add(DateTime.utc_now(), 10, :day))
  end

  test "C20: usage counts of yesterday that did not go", context do
    yesterday = Date.add(Date.utc_today(), -1)
    morning = DateTime.new!(Date.utc_today(), ~T[02:00:00], "Etc/UTC")
    noon = DateTime.new!(Date.utc_today(), ~T[12:00:00], "Etc/UTC")

    assert %{level: :ok} = check(Checks.UsageSends, context, noon)

    settings =
      Ash.Seed.seed!(Rescord.Usage.Settings, %{
        mode: :send,
        endpoint: "https://usage.example.org",
        sending_since: Date.add(yesterday, -3)
      })

    assert %{level: :ok} = check(Checks.UsageSends, context, morning)
    assert %{level: :fail, ids: [found]} = check(Checks.UsageSends, context, noon)
    assert found == settings.id

    Repo.query!("update usage_settings set last_sent_day = $1", [yesterday])
    assert %{level: :ok} = check(Checks.UsageSends, context, noon)
  end

  test "C21: a notification that did not leave, and one that stays too long", context do
    assert %{level: :ok} = check(Checks.Notifications, context)

    {:ok, _comment} =
      Comments.write(
        {:resident, context.biscuit.id},
        %{body: "She limps.", told_ids: [context.member.id]},
        context.options
      )

    # The listener makes the notification; its job has not run yet, and
    # it has 2 hours.
    Oban.drain_queue(queue: :default, with_safety: false)
    assert %{level: :ok} = check(Checks.Notifications, context)

    sql!(context, "update @notifications set inserted_at = now() - interval '3 hours'", [])
    assert %{level: :fail, count: 1} = check(Checks.Notifications, context)

    sql!(
      context,
      "update @notifications set delivered_at = now(), read_at = now() - interval '40 days'",
      []
    )

    assert %{level: :fail, count: 1} = check(Checks.Notifications, context)
  end

  test "C22: a transfer that failed a week ago, and one that waits", context do
    assert %{level: :ok} = check(Checks.Transfers, context)

    banksia = organisation!(context.root, "Banksia Rise")
    {_, banksia_admin} = member!(banksia, :administrator, context.root)

    {:ok, asked} =
      Transfers.ask_partner(context.organisation, banksia.short_name,
        actor: context.administrator
      )

    {:ok, _accepted} = Transfers.accept_partner(asked, actor: banksia_admin)

    {:ok, transfer} =
      Transfers.send_transfer(
        %{
          organisation_id: context.organisation.id,
          partner_id: banksia.id,
          resident_id: context.biscuit.id,
          parts: []
        },
        actor: context.administrator
      )

    Repo.query!(
      "update transfers set state = 'sent', sent_at = now() - interval '15 days' where id = $1",
      [uuid(transfer.id)]
    )

    assert %{level: :note, ids: [found]} = check(Checks.Transfers, context)
    assert found == transfer.id

    Repo.query!("update transfers set state = 'failed' where id = $1", [uuid(transfer.id)])
    assert %{level: :fail, ids: [^found]} = check(Checks.Transfers, context)
  end

  describe "C23: the backups" do
    setup %{tmp_dir: tmp_dir} do
      dir = Path.join(tmp_dir, "backups")
      previous = Application.get_env(:rescord, :backup_dir)
      on_exit(fn -> Application.put_env(:rescord, :backup_dir, previous) end)
      {:ok, dir: dir}
    end

    defp dump!(dir, name, bytes, hours_ago) do
      path = Path.join([dir, "database", name])
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, bytes)
      File.touch!(path, System.os_time(:second) - hours_ago * 3_600)
    end

    test "finds nothing with no directory, and each fault with one", context do
      Application.put_env(:rescord, :backup_dir, nil)
      assert %{level: :ok} = check(Checks.Backups, context)

      Application.put_env(:rescord, :backup_dir, context.dir)
      assert %{level: :fail} = check(Checks.Backups, context)

      dump!(context.dir, "rescord-20261126T030000Z.dump", "PGDMP", 30)
      assert %{level: :fail} = check(Checks.Backups, context)

      dump!(context.dir, "rescord-20261127T030000Z.dump", "", 2)
      assert %{level: :fail} = check(Checks.Backups, context)

      dump!(context.dir, "rescord-20261128T030000Z.dump", "PGDMP", 1)
      assert %{level: :ok} = check(Checks.Backups, context)

      dump!(context.dir, "rescord-20261125T030000Z.dump.partial", "PG", 72)
      dump!(context.dir, "rescord-20261128T040000Z.dump.partial", "PG", 0)
      assert %{level: :note, count: 1} = check(Checks.Backups, context)
    end
  end
end
