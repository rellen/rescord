defmodule RescordWeb.ExpenseFileController do
  @moduledoc """
  Sends the expenses of an organisation as a CSV file, at
  `/o/<short name>/expenses.csv` (ADR 0082).

  The file holds the expenses that the person reads, within the limits that
  the address names. They are the ones of the list on the page of the
  expenses: `search`, `status`, `category_id`, `paid_by`, `incurred_on` as
  two dates with a comma between them, and `resident`. A limit that is not
  one of those, or that has a value that is no value, limits nothing.

  The file needs no power of its own: it holds what the page shows. It is
  for a person, and for the import of the system that does the accounts, so
  it has words where the export of the data (ADR 0054) has ids. The amount
  is a number, and the code of its currency is in the next column.
  """

  use RescordWeb, :controller

  alias Rescord.{Accounts, Expenses}
  alias RescordWeb.ExpenseWords

  def index(conn, %{"organisation" => short_name} = params) do
    with %{} = user <- conn.assigns[:current_user],
         {:ok, organisation, _member} <- Accounts.organisation_for(user, short_name),
         options = [actor: user, tenant: organisation],
         {:ok, expenses} <- Expenses.report(limits(params), options),
         {:ok, members} <- Accounts.members([load: [:email]] ++ options) do
      # The words of the file are in the locale of the organisation.
      RescordWeb.Locale.put(organisation)
      people = Map.new(members, &{&1.user_id, to_string(&1.email)})
      rows = Enum.map(expenses, &ExpenseWords.csv_row(&1, organisation, people))
      today = Date.to_iso8601(Accounts.today(organisation))

      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> send_download(
        {:binary,
         IO.iodata_to_binary(Rescord.Export.CSV.encode(ExpenseWords.csv_header(), rows))},
        filename: "expenses-#{organisation.short_name}-#{today}.csv",
        content_type: "text/csv",
        charset: "utf-8"
      )
    else
      _no -> not_found(conn)
    end
  end

  @doc """
  The limits of `Rescord.Expenses.report/2` from the fields of an address.
  It makes no atom, and leaves out each field that it does not know.

      iex> RescordWeb.ExpenseFileController.limits(%{"status" => "to_pay_back", "paid_by" => "member"})
      %{status: :to_pay_back, paid_by: :member}

      iex> RescordWeb.ExpenseFileController.limits(%{"incurred_on" => "2026-11-01,2026-11-30", "search" => " vet "})
      %{from: ~D[2026-11-01], to: ~D[2026-11-30], search: "vet"}

      iex> RescordWeb.ExpenseFileController.limits(%{"incurred_on" => ",2026-11-30", "status" => "paid", "page" => "2"})
      %{to: ~D[2026-11-30]}
  """
  @spec limits(map) :: Expenses.limits()
  def limits(params) do
    Enum.reduce(params, %{}, fn
      {"search", text}, limits when is_binary(text) ->
        if String.trim(text) == "", do: limits, else: Map.put(limits, :search, String.trim(text))

      {"status", text}, limits ->
        case ExpenseWords.status_of(text) do
          {:ok, status} -> Map.put(limits, :status, status)
          :error -> limits
        end

      {"paid_by", text}, limits ->
        case ExpenseWords.paid_by_of(text) do
          {:ok, paid_by} -> Map.put(limits, :paid_by, paid_by)
          :error -> limits
        end

      {"category_id", id}, limits ->
        put_id(limits, :category_id, id)

      {"resident", id}, limits ->
        put_id(limits, :resident_id, id)

      {"incurred_on", text}, limits when is_binary(text) ->
        case String.split(text, ",") do
          [from, to] -> limits |> put_date(:from, from) |> put_date(:to, to)
          _other -> limits
        end

      _other, limits ->
        limits
    end)
  end

  defp put_id(limits, key, id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Map.put(limits, key, uuid)
      :error -> limits
    end
  end

  defp put_id(limits, _key, _other), do: limits

  defp put_date(limits, key, text) do
    case Date.from_iso8601(text) do
      {:ok, date} -> Map.put(limits, key, date)
      {:error, _not_a_date} -> limits
    end
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(html: RescordWeb.ErrorHTML)
    |> render(:"404")
  end
end
