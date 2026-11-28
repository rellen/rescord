defmodule RescordWeb.GroupPagesTest do
  @moduledoc """
  Holds the pages of the groups, and the family and groups part of the page
  of a resident: who can open each page, and what a form does. The tests
  find what a person finds (ADR 0107).

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Phoenix.LiveViewTest, only: [render_click: 3]
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.Residents

  setup context do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, member} = member!(organisation, :member, root)
    lists = lists!(organisation, root)
    options = [actor: member, tenant: organisation]
    pig = fn name, sex -> resident!(lists, options, %{name: name, sex: sex}) end

    {:ok,
     root: root,
     organisation: organisation,
     member: member,
     base: ~p"/o/#{organisation.short_name}",
     options: options,
     conn: sign_in(context.conn, member),
     fern: pig.("Fern", :female),
     sage: pig.("Sage", :female),
     basil: pig.("Basil", :male)}
  end

  defp sisters!(context) do
    litter = Residents.name_family!("The spring litter", context.options)

    for resident <- [context.fern, context.sage] do
      Residents.add_to_family!(%{resident_id: resident.id, family_id: litter.id}, context.options)
    end

    litter
  end

  defp title(name), do: main() |> heading(name, level: 1)
  defp related, do: main() |> region("About") |> definition("How they are related")
  defp relations, do: main() |> region("Family and groups")

  test "the pages do not open for a user of another organisation, or with no sign-in", context do
    other = organisation!(context.root, "Other")
    {_, outsider} = member!(other, :administrator, context.root)
    group = Residents.form_group!(%{resident_ids: [context.fern.id]}, context.options)

    for path <- ["/groups", "/groups/#{group.id}"] do
      build_conn() |> sign_in(outsider) |> visit(context.base <> path) |> assert_path("/")
      build_conn() |> visit(context.base <> path) |> assert_path("/")
    end

    context.conn
    |> visit(context.base <> "/groups/#{Ash.UUID.generate()}")
    |> assert_path(context.base <> "/groups")
    |> assert_has(alert(), text: "There is no such group.")
  end

  describe "the groups page" do
    test "makes a group with its first members, and lists it with its words", context do
      sisters!(context)

      context.conn
      |> visit(context.base <> "/groups")
      |> assert_has(main(), text: "No group yet.")
      |> check("Basil")
      |> check("Fern")
      |> check("Sage")
      |> click_button("Add the group")
      # The page of the new group.
      |> assert_has(title("Basil, Fern and Sage"))
      |> assert_has(related(), text: "Sisters and an unrelated male")

      context.conn
      |> visit(context.base <> "/groups")
      |> assert_has(main() |> row(~r/^Basil, Fern and Sage\b/),
        text: "Sisters and an unrelated male"
      )
      |> refute_has(main(), text: "No group yet.")
    end
  end

  describe "the page of a group" do
    setup context do
      sisters!(context)

      group =
        Residents.form_group!(
          %{resident_ids: [context.fern.id, context.sage.id]},
          context.options
        )

      {:ok, group: group, path: context.base <> "/groups/#{group.id}"}
    end

    test "takes the time that a resident joined the group and left it", context do
      names = fn instant ->
        {:ok, group} =
          Residents.group_with_facts(context.group.id, [as_of: instant] ++ context.options)

        Enum.map(group.members, & &1.resident.name)
      end

      # A time some seconds ago, as a member types it.
      ago = fn seconds ->
        DateTime.utc_now()
        |> DateTime.add(-seconds, :second)
        |> DateTime.shift_zone!(context.organisation.time_zone)
        |> DateTime.to_naive()
        |> NaiveDateTime.truncate(:second)
        |> NaiveDateTime.to_iso8601()
      end

      session = visit(context.conn, context.path)
      before = DateTime.utc_now()
      Process.sleep(2100)

      session =
        session
        |> select("Resident", option: "Basil")
        |> fill_in("When it joined the group, if not now", with: ago.(1))
        |> click_button("Add to the group")

      joined = DateTime.utc_now()
      assert names.(before) == ["Fern", "Sage"]
      assert names.(joined) == ["Basil", "Fern", "Sage"]
      Process.sleep(3100)

      session =
        session
        |> fill_in("When Basil left the group, if not now", with: ago.(1))
        |> click_button("Take Basil out of the group")

      assert names.(joined) == ["Basil", "Fern", "Sage"]
      assert names.(DateTime.utc_now()) == ["Fern", "Sage"]

      # A time after now is refused.
      tomorrow =
        context.organisation |> Rescord.Accounts.today() |> Date.add(1) |> Date.to_iso8601()

      session
      |> select("Resident", option: "Basil")
      |> fill_in("When it joined the group, if not now", with: tomorrow <> "T08:00")
      |> click_button("Add to the group")
      |> assert_has(main() |> alert(), text: "The time cannot be after now")

      assert names.(DateTime.utc_now()) == ["Fern", "Sage"]
    end

    test "adds a member and takes one out, and the words follow", context do
      context.conn
      |> visit(context.path)
      |> assert_has(title("Fern and Sage"))
      |> assert_has(related(), text: "Sisters")
      |> select("Resident", option: "Basil")
      |> click_button("Add to the group")
      |> assert_has(related(), text: "Sisters and an unrelated male")
      # Each resident is in the group now, so there is nobody to add.
      |> refute_has(main() |> details("Add a resident"))
      |> click_button("Take Fern out of the group")
      |> assert_has(title("Basil and Sage"))
      |> assert_has(related(), text: "No relation is recorded")
      # A member that is not one of this group does nothing.
      |> unwrap(&render_click(&1, "leave", %{"member_id" => Ash.UUID.generate()}))
      |> refute_has(main() |> alert())
      |> assert_has(title("Basil and Sage"))
    end

    test "takes a name and the words of a member, and gives the words of Rescord again",
         context do
      change = fn session, fields ->
        within(session, main() |> details("Change the group"), fn form ->
          fields
          |> Enum.reduce(form, fn {label, words}, form -> fill_in(form, label, with: words) end)
          |> click_button("Save the group")
        end)
      end

      session =
        context.conn
        |> visit(context.path)
        |> change.(%{
          "Name, if the group has one" => "The East 1 pair",
          "How they are related" => "Bonded at intake"
        })
        |> assert_has(title("The East 1 pair"))

      assert text(session, related()) == "Bonded at intake (the words of a member)"

      session = change.(session, %{"How they are related" => ""})
      assert text(session, related()) == "Sisters"
    end

    test "closes the group", context do
      context.conn
      |> visit(context.path)
      |> click(button("Close the group"))
      |> assert_path(context.base <> "/groups")
      |> assert_has(status(), text: "The group is closed.")
      |> assert_has(main(), text: "No group yet.")
    end
  end

  describe "the family and groups of a resident" do
    setup context do
      {:ok, path: context.base <> "/residents/#{context.fern.id}"}
    end

    test "adds a parent and removes it, and the parent shows its young", context do
      basil = context.base <> "/residents/#{context.basil.id}"

      context.conn
      |> visit(context.path)
      |> assert_has(relations(), text: "No parent is recorded.")
      |> select("Parent", option: "Basil")
      |> select("Mother or father", option: "Father")
      |> click_button("Add the parent")
      |> assert_has(relations() |> item(~r/^Father: Basil\b/))
      |> assert_has(relations() |> button("Remove the father Basil"))

      context.conn
      |> visit(basil)
      |> assert_has(relations() |> heading("Young", level: 3))
      |> assert_has(relations() |> link("Fern"))
      # A resident is not a parent of its own parent.
      |> select("Parent", option: "Fern")
      |> select("Mother or father", option: "Mother")
      |> click_button("Add the parent")
      |> assert_has(main() |> alert(), text: "is one of the young of this resident")

      context.conn
      |> visit(context.path)
      |> click(relations() |> button("Remove the father Basil"))
      |> assert_has(relations(), text: "No parent is recorded.")
    end

    test "adds the resident to a new family and to one that is there", context do
      context.conn
      |> visit(context.path)
      |> assert_has(relations(), text: "The resident is in no family.")
      |> click_button("Add to the family")
      |> assert_has(main() |> alert(), text: "Choose a family, or give a new one a name")
      |> fill_in("Or the name of a new family", with: "The spring litter")
      |> click_button("Add to the family")
      |> assert_has(relations() |> item(~r/^The spring litter\b/))

      # The page of another resident offers the family that is there now.
      context.conn
      |> visit(context.base <> "/residents/#{context.sage.id}")
      |> select("A family that is there", option: "The spring litter")
      |> click_button("Add to the family")
      |> assert_has(relations() |> item(~r/^The spring litter\b/))

      assert [_one] = Residents.families!(context.options)
    end

    test "shows the groups of the resident with their words", context do
      sisters!(context)
      Residents.form_group!(%{resident_ids: [context.fern.id, context.sage.id]}, context.options)

      context.conn
      |> visit(context.path)
      |> assert_has(relations() |> item(~r/^Fern and Sage\b/), text: "(Sisters)")
    end
  end
end
