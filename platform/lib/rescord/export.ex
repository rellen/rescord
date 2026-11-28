defmodule Rescord.Export do
  @moduledoc """
  The export of the data of an organisation (ADR 0054): one ZIP with a CSV
  file for each table, and a README that says what each file holds.

  The person who asks needs the power `export`, which
  `Rescord.Accounts.authorize_export/2` checks first. The export then reads
  each table as that person, in the schema of the organisation.

  A temporal resource is read as it stood at the end of the chosen day in
  the time zone of the organisation, or now for today. A resource that keeps
  no history, such as a task, is read as it is now; the README names those
  files.

  The tables are each resource of the domains of `@domains`, the
  organisation, its roles and its members, and the shared base lists that
  the lists of the organisation name. `excluded/0` gives each resource that
  is left out, with the reason. `Rescord.ExportTest` holds each resource of
  the domains of the configuration to one of the two.

  The photos and the PDFs of the journal are not in the export:
  `journal_attachments.csv` lists each one.
  """

  use Boundary,
    top_level?: true,
    deps: [
      Rescord,
      Rescord.Accounts,
      Rescord.Lists,
      Rescord.Residents,
      Rescord.Locations,
      Rescord.Journal,
      Rescord.Photos,
      Rescord.Tasks,
      Rescord.Inventory,
      Rescord.Expenses,
      Rescord.Comments,
      Rescord.Privacy
    ],
    # A page that sends one table as a file writes it with the same CSV.
    exports: [CSV]

  require Logger

  alias Rescord.Accounts
  alias Rescord.Accounts.{Member, Organisation, Role}
  alias Rescord.Export.CSV
  alias Rescord.Export.Errors.{InvalidDate, Unreadable}

  @domains [
    Rescord.Lists,
    Rescord.Residents,
    Rescord.Locations,
    Rescord.Journal,
    Rescord.Photos,
    Rescord.Tasks,
    Rescord.Inventory,
    Rescord.Expenses,
    Rescord.Comments,
    Rescord.Privacy
  ]

  # Columns that are calculations, after the attributes.
  @calculations %{
    Member => [:email, :former?],
    # A measurement in the standard unit of its kind (ADR 0094), beside the
    # value and the unit that the person recorded.
    Rescord.Journal.Measurement => [:standard_value, :standard_unit]
  }

  @excluded %{
    Rescord.Accounts.User =>
      "A user can belong to several organisations. members.csv has the email of each member.",
    Rescord.Accounts.Token => "The tokens of the sign-in are secrets of a session.",
    Rescord.Transfers.Partnership => "A partnership belongs to two refuges.",
    Rescord.Transfers.Transfer =>
      "A transfer belongs to two refuges, and a transfer file carries a resident to another one.",
    Rescord.Transfers.RemotePartner =>
      "A partner on another server is the setting of the transfers between servers.",
    Rescord.Transfers.RefugeKey => "The keys of a refuge are secrets of the transfers.",
    Rescord.Ruby.Provider =>
      "A provider of the assistant is a setting of the server, and no record of a rescue.",
    Rescord.Calendars.Feed =>
      "A calendar feed is a setting of one member, and its row holds the hash of the secret of its address.",
    Rescord.Reports.Report =>
      "A report is a document that an action writes from the other records. It has no table.",
    Rescord.Ruby.Conversation =>
      "A conversation with the assistant is the working notes of one member, and no record " <>
        "of the rescue. Each thing that the assistant helped to write is in its own file.",
    Rescord.Ruby.Message =>
      "A message of a conversation with the assistant: see ruby_conversations.",
    Rescord.Ruby.Settings =>
      "How the organisation uses the assistant is a setting that names a provider of this " <>
        "server, and no record of the rescue.",
    Rescord.Ruby.Usage =>
      "The use of the assistant is counts of tokens for the bill of this server, and no " <>
        "record of the rescue.",
    Rescord.Usage.Count =>
      "The usage counts are of the whole server, with no organisation in them (ADR 0098).",
    Rescord.Usage.Settings =>
      "What the server does with its usage counts is a setting of the server (ADR 0098).",
    Rescord.Comments.Follow =>
      "Who follows a record is a setting of each member for their notifications (ADR 0106).",
    Rescord.Notifications.Notification =>
      "A notification is a pointer to a comment for one member, and goes after 90 days. " <>
        "comments.csv has each comment.",
    Rescord.Notifications.Preference =>
      "Where the notifications of a member go is a setting of that member.",
    Rescord.Notifications.PushSubscription =>
      "A device of a person is a secret of the push service, and of no organisation.",
    Rescord.Notifications.NtfyTopic =>
      "The topic of ntfy of a person is a secret, and of no organisation.",
    Rescord.Notifications.Settings =>
      "The channels of the notifications are a setting of the server, with its keys (ADR 0106)."
  }

  @typedoc "An export: the name of the file and the bytes of the ZIP."
  @type t :: %{filename: String.t(), zip: binary}

  @doc """
  The export of `organisation` as it stood at the end of `date`, for the
  person `actor`. Returns `{:error, :forbidden}` when the role of the person
  has no power `export`, an `InvalidDate` error for a date that is not a
  date or that is after today, and an `Unreadable` error for a table that
  it could not read. `Rescord.Accounts.error_messages/1` says each error in
  words.
  """
  @spec export(Ash.Resource.record(), Date.t() | term, keyword) ::
          {:ok, t} | {:error, :forbidden | InvalidDate.t() | Unreadable.t()}
  def export(%Organisation{} = organisation, date, opts) do
    actor = Keyword.fetch!(opts, :actor)
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with :ok <- authorize(organisation, actor),
         {:ok, instant} <- instant(organisation, date, now),
         {:ok, tables} <- tables(organisation, actor, instant) do
      folder = "rescord-#{organisation.short_name}-#{Date.to_iso8601(date)}"

      files =
        [{"README.txt", readme(organisation, date, instant, now, tables)}] ++
          Enum.map(tables, fn {file, _resource, header, rows} ->
            {file, IO.iodata_to_binary(CSV.encode(header, rows))}
          end)

      entries = for {file, bytes} <- files, do: {String.to_charlist("#{folder}/#{file}"), bytes}
      {:ok, {_name, zip}} = :zip.create(~c"#{folder}.zip", entries, [:memory])
      {:ok, %{filename: "#{folder}.zip", zip: zip}}
    end
  end

  @doc "The resources of the export, in the order of their files."
  @spec resources() :: [module]
  def resources do
    [Organisation, Role, Member] ++
      for domain <- @domains,
          resource <- Ash.Domain.Info.resources(domain),
          not version?(resource),
          # A domain of the export can hold a setting of one member.
          not Map.has_key?(@excluded, resource),
          do: resource
  end

  @doc "Each resource that the export leaves out, with the reason."
  @spec excluded() :: %{module => String.t()}
  def excluded, do: @excluded

  @doc "Whether a resource is a version that a paper trail adds."
  @spec version?(module) :: boolean
  def version?(resource), do: String.ends_with?(inspect(resource), ".Version")

  @doc "The name of the file of a resource in the export."
  @spec file(module) :: String.t()
  def file(Organisation), do: "organisation.csv"
  def file(resource), do: "#{AshPostgres.DataLayer.Info.table(resource)}.csv"

  defp authorize(organisation, actor) do
    case Accounts.authorize_export(organisation.id, actor: actor) do
      {:ok, true} -> :ok
      {:error, _forbidden} -> {:error, :forbidden}
    end
  end

  # The end of the day in the time zone of the organisation, and not after now.
  defp instant(organisation, %Date{} = date, now) do
    if Date.compare(date, Accounts.local_date(organisation, now)) == :gt do
      {:error, InvalidDate.exception(reason: :after_today)}
    else
      {_start, next} = Accounts.day_range(organisation, date)
      last = DateTime.add(next, -1, :microsecond)
      {:ok, if(DateTime.compare(last, now) == :gt, do: now, else: last)}
    end
  end

  defp instant(_organisation, _date, _now),
    do: {:error, InvalidDate.exception(reason: :not_a_date)}

  defp tables(organisation, actor, instant) do
    Enum.reduce_while(resources(), {:ok, []}, fn resource, {:ok, tables} ->
      case rows(resource, organisation, actor, instant) do
        {:ok, records} ->
          columns = columns(resource)

          rows =
            for record <- records, do: Enum.map(columns, fn {_name, read} -> read.(record) end)

          header = Enum.map(columns, fn {name, _read} -> name end)
          {:cont, {:ok, [{file(resource), resource, header, rows} | tables]}}

        {:error, error} ->
          # The message of an error can hold a value of a record, so the page
          # gets the name of the file, and the log gets the kind of the error.
          Logger.error(
            "The export could not read #{file(resource)}: #{Rescord.Log.reason(error)}"
          )

          {:halt, {:error, Unreadable.exception(file: file(resource))}}
      end
    end)
    |> case do
      {:ok, tables} -> {:ok, Enum.reverse(tables)}
      error -> error
    end
  end

  # The columns of a resource, each as its name and the function that reads
  # its cell from a record. An amount of money is two columns: the number,
  # and the code of its currency (ADR 0082).
  defp columns(resource) do
    attributes =
      Enum.flat_map(Ash.Resource.Info.public_attributes(resource), fn
        %{name: name, type: AshMoney.Types.Money} ->
          [
            {Atom.to_string(name), &money_part(Map.get(&1, name), :amount)},
            {"#{name}_currency", &money_part(Map.get(&1, name), :currency)}
          ]

        %{name: name} ->
          [{Atom.to_string(name), &Map.get(&1, name)}]
      end)

    attributes ++
      for name <- Map.get(@calculations, resource, []),
          do: {Atom.to_string(name), &Map.get(&1, name)}
  end

  defp money_part(%Money{} = money, part), do: Map.fetch!(money, part)
  defp money_part(_no_money, _part), do: nil

  # Only a root user reads an organisation through its actions; the export
  # is already allowed, and holds the one row of this organisation.
  defp rows(Organisation, organisation, _actor, _instant), do: {:ok, [organisation]}

  defp rows(resource, organisation, actor, instant) do
    tenant =
      if Ash.Resource.Info.multitenancy_strategy(resource) == :context,
        do: [tenant: organisation],
        else: []

    as_of = if Ash.Resource.Info.temporal?(resource), do: [as_of: instant], else: []
    keys = Ash.Resource.Info.primary_key(resource)

    resource
    |> read_action()
    |> Ash.Query.sort(Enum.map(keys, &{&1, :asc}))
    |> Ash.Query.load(Map.get(@calculations, resource, []))
    |> Ash.read([actor: actor] ++ tenant ++ as_of)
  end

  # members.csv holds the former members too, so that each id of a record
  # names a row (ADR 0105).
  defp read_action(Member), do: Ash.Query.for_read(Member, :with_former)
  defp read_action(resource), do: Ash.Query.new(resource)

  defp readme(organisation, date, instant, now, tables) do
    local = Accounts.local_time(organisation, instant)
    exported = MapSet.new(tables, fn {_file, resource, _header, _rows} -> resource end)

    {history, present} =
      Enum.split_with(tables, fn {_file, resource, _header, _rows} ->
        Ash.Resource.Info.temporal?(resource)
      end)

    """
    The data of #{organisation.name} in Rescord

    As of: the end of #{Date.to_iso8601(date)} in #{organisation.time_zone}, which is
    #{Calendar.strftime(local, "%Y-%m-%d %H:%M:%S")} there and #{DateTime.to_iso8601(instant)}.
    Made: #{DateTime.to_iso8601(now)}.

    Each file is a table in CSV: UTF-8 with a byte order mark, commas, a header
    row, and CRLF at the end of each row. A date and a time are in ISO 8601,
    a time in UTC. A list has "; " between its values, and a map is JSON. A
    text that starts with =, +, -, @, a tab or a carriage return has a ' before
    it, so that a spreadsheet does not run it as a formula. An amount of money
    is two columns: the number, and the code of its currency in the column
    with the same name and _currency at its end.

    These files are as they stood at that time:

    #{list(history)}

    These files keep no history, so they are as they are now:

    #{list(present)}

    A column that ends in _id holds the id of a row of another file:

    #{links(tables, exported)}

    Not in the export:

    - The photos and the PDFs of the journal. journal_attachments.csv lists
      each one, and the person who exports can open each one in Rescord.
    - The files of the receipts of the expenses. expense_receipts.csv lists
      each one. expenses.csv holds the expenses that the person who exports
      can read: each one for a person who manages the expenses.
    #{Enum.map_join(@excluded, "\n", fn {resource, why} -> "- #{inspect(resource)}: #{why}" end)}
    """
  end

  defp list(tables) do
    Enum.map_join(tables, "\n", fn {file, _resource, header, rows} ->
      "- #{file} (#{length(rows)} rows): #{Enum.join(header, ", ")}"
    end)
  end

  defp links(tables, exported) do
    for {file, resource, _header, _rows} <- tables,
        %{type: :belongs_to} = relationship <- Ash.Resource.Info.relationships(resource),
        relationship.destination in exported do
      "- #{file}: #{relationship.source_attribute} names a row of #{file(relationship.destination)}"
    end
    |> Enum.join("\n")
  end
end
