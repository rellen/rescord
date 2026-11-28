defmodule Rescord.Ruby.CatalogueTest do
  @moduledoc """
  Holds the tools of the assistant to the catalogue (ADR 0069): a tool
  that a domain declares is in the catalogue, no tool is on a destroy
  action or on an action that never has one, and only the domains that
  this test names have tools at all.

  It reads the declarations, and needs no database and no model.
  """

  use ExUnit.Case, async: true

  alias Rescord.Ruby.Catalogue

  # The domains that may declare a tool. Each other domain has no tool and
  # not even the extension: the accounts, the lists, the photos, the
  # transfers and Ruby itself never get one (ADR 0069), and a new domain
  # gets one only with a line here.
  @with_tools [Rescord.Residents, Rescord.Tasks]

  # The actions that never have a tool, in the domains that may declare
  # one: what changes who a resident is, and what hands a task to a member
  # or removes it.
  @never [
    {Rescord.Residents.Resident, [:register, :revise, :remove]},
    {Rescord.Tasks.Task, [:revise, :give, :cancel, :generate]}
  ]

  defp domains, do: Application.fetch_env!(:rescord, :ash_domains)

  defp declared do
    for domain <- domains(), AshAi in Ash.Domain.Info.extensions(domain) do
      for tool <- AshAi.Info.tools(domain), do: {domain, tool}
    end
    |> List.flatten()
  end

  defp action({_domain, tool}), do: Ash.Resource.Info.action(tool.resource, tool.action)

  test "only the domains of the list have the extension, and no resource has it" do
    with_extension = Enum.filter(domains(), &(AshAi in Ash.Domain.Info.extensions(&1)))
    assert Enum.sort(with_extension) == Enum.sort(@with_tools)

    for domain <- domains(), resource <- Ash.Domain.Info.resources(domain) do
      refute AshAi in Ash.Resource.Info.extensions(resource),
             "#{inspect(resource)} declares tools of its own"
    end
  end

  test "each tool that a domain declares is in the catalogue, as an action tool" do
    assert declared() != []

    for {domain, tool} <- declared() do
      entry = Catalogue.entry(Atom.to_string(tool.name))

      assert %{source: :action} = entry,
             "#{tool.name} of #{inspect(domain)} is not an action tool of the catalogue"
    end
  end

  test "each action tool of the catalogue is declared, one time" do
    names = for {_domain, tool} <- declared(), do: tool.name
    assert names == Enum.uniq(names)

    for %{source: :action, name: name} <- Catalogue.entries() do
      assert name in names, "no domain declares #{name}"
    end
  end

  test "a read of the catalogue is a read action, and a write is none" do
    for {_domain, tool} = declaration <- declared() do
      entry = Catalogue.entry(Atom.to_string(tool.name))
      type = action(declaration).type

      case entry.kind do
        :read -> assert type == :read, "#{tool.name} is a read of the catalogue on a #{type}"
        :write -> assert type in [:create, :update], "#{tool.name} is a write on a #{type}"
      end
    end
  end

  test "no tool is on a destroy action, or on an action that never has one" do
    for {resource, names} <- @never, name <- names do
      # The list names actions that exist: a new name of an action must
      # not empty it.
      assert Ash.Resource.Info.action(resource, name),
             "#{inspect(resource)} has no action #{name}"
    end

    for {_domain, tool} = declaration <- declared() do
      refute action(declaration).type == :destroy, "#{tool.name} is on a destroy action"

      refute tool.action in Keyword.get(@never, tool.resource, []),
             "#{tool.name} is on an action that never has a tool"
    end
  end

  test "a digest is a module with the name of its entry, and each name is one of a kind" do
    names = Enum.map(Catalogue.entries(), & &1.name)
    assert names == Enum.uniq(names)

    for %{source: {:extra, module}, name: name} <- Catalogue.entries() do
      {%ReqLLM.Tool{} = tool, run} = module.tool()
      assert tool.name == Atom.to_string(name)
      assert module.name() == tool.name
      assert is_function(run, 2)
      assert tool.description =~ "_text"
      # Without the context of a member the tool does nothing.
      assert {:error, _words} = tool.callback.(%{})
      refute module.available?(nil, "org_none")
    end
  end

  test "each tool has a description, and a name of a verb and a noun" do
    for {_domain, tool} <- declared() do
      assert is_binary(tool.description) and tool.description != ""
      assert Atom.to_string(tool.name) =~ ~r/^[a-z]+(_[a-z]+)+$/
    end
  end

  test "the catalogue finds a tool by the text of its name, and makes no atom" do
    assert %{name: :find_residents, kind: :read} = Catalogue.entry("find_residents")
    assert Catalogue.read?("tasks_for_day")

    for name <- ["remove_resident", "no_such_tool_#{System.unique_integer([:positive])}", nil, 7] do
      assert Catalogue.entry(name) == nil
      refute Catalogue.read?(name)
    end
  end

  test "each tool that is on is a read: the loop gets no write" do
    on = Catalogue.on(%{enabled: true}, %{provider: :anthropic})
    assert on != []
    assert Enum.all?(on, &(&1.kind == :read))
    assert on == Enum.filter(Catalogue.entries(), &(&1.kind == :read))
  end
end
