defmodule RescordWeb.ReportController do
  @moduledoc """
  Sends a report as a PDF (ADR 0076):

    * `/o/<short name>/residents/<id>/record.pdf`: the record of a resident,
      with `journal` (`medical`, `all` or `none`) and `photos` (`true`);
    * `/o/<short name>/residents/<id>/card.pdf`: its cage card;
    * `/o/<short name>/reports/register.pdf`, with `on`;
    * `/o/<short name>/reports/movements.pdf`, with `from` and `to`;
    * `/o/<short name>/reports/tasks.pdf`, with `on`;
    * `/o/<short name>/reports/stock.pdf` and `/o/<short name>/reports/housing.pdf`;
    * `/o/<short name>/reports/expenses.pdf`, with `from` and `to`.

  Each takes `paper`, `a4` or `us_letter` (ADR 0093). With none, and with
  another value, the document is on the paper of the organisation.

  Each is a `GET`, so a link and a form with no script can ask for one, and
  a download goes through a controller, because a page of LiveView cannot
  send a file. The action of `Rescord.Reports` runs as the person, in their
  organisation, so the policy decides who gets the document and the reads
  decide what is in it.

  The browser shows the PDF and can print it, and it keeps no copy in a
  cache. A report that the person cannot make, and a resident that is not
  there, get the same answer: no such page. A date that is not right goes
  back to the page of the reports with words. A person who made too many
  reports in a minute reads that they must wait (ADR 0020).

  The answer has no `sandbox` policy, unlike the file of an attachment: a
  browser does not show a PDF in a sandbox, and the document is one that
  Rescord wrote, with text and pictures and no script.
  """

  use RescordWeb, :controller

  alias Rescord.{Accounts, Reports, Residents}

  def resident_record(conn, %{"id" => id} = params) do
    with_resident(conn, params, fn resident, organisation, options ->
      arguments =
        Map.merge(paper(params), %{
          journal: journal(params["journal"]),
          photos: params["photos"] == "true"
        })

      id
      |> Reports.resident_record(arguments, options)
      |> answer(conn, organisation, file_name(resident, "record", organisation))
    end)
  end

  def cage_card(conn, %{"id" => id} = params) do
    with_resident(conn, params, fn resident, organisation, options ->
      id
      |> Reports.cage_card(paper(params), options)
      |> answer(conn, organisation, file_name(resident, "cage-card", organisation))
    end)
  end

  def register(conn, params) do
    with_organisation(conn, params, fn organisation, options ->
      with {:ok, on} <- date(params["on"]) do
        params
        |> paper()
        |> Map.put(:on, on)
        |> Reports.register(options)
        |> answer(conn, organisation, "register-#{day(on, organisation)}.pdf")
      end
    end)
  end

  def movements(conn, params) do
    with_organisation(conn, params, fn organisation, options ->
      with {:ok, %Date{} = from} <- date(params["from"]),
           {:ok, %Date{} = to} <- date(params["to"]) do
        from
        |> Reports.movements(to, paper(params), options)
        |> answer(conn, organisation, "movements-#{from}-to-#{to}.pdf")
      else
        {:ok, nil} -> {:error, "Give a day in From and a day in To."}
        error -> error
      end
    end)
  end

  def task_sheet(conn, params) do
    with_organisation(conn, params, fn organisation, options ->
      with {:ok, on} <- date(params["on"]) do
        params
        |> paper()
        |> Map.put(:on, on)
        |> Reports.task_sheet(options)
        |> answer(conn, organisation, "tasks-#{day(on, organisation)}.pdf")
      end
    end)
  end

  def stock(conn, params) do
    with_organisation(conn, params, fn organisation, options ->
      params
      |> paper()
      |> Reports.stock(options)
      |> answer(conn, organisation, "stock-#{day(nil, organisation)}.pdf")
    end)
  end

  def housing(conn, params) do
    with_organisation(conn, params, fn organisation, options ->
      params
      |> paper()
      |> Reports.housing(options)
      |> answer(conn, organisation, "housing-#{day(nil, organisation)}.pdf")
    end)
  end

  def expenses(conn, params) do
    with_organisation(conn, params, fn organisation, options ->
      with {:ok, %Date{} = from} <- date(params["from"]),
           {:ok, %Date{} = to} <- date(params["to"]) do
        from
        |> Reports.expenses(to, paper(params), options)
        |> answer(conn, organisation, "expenses-#{from}-to-#{to}.pdf")
      else
        {:ok, nil} -> {:error, "Give a day in From and a day in To."}
        error -> error
      end
    end)
  end

  # Runs `fun` for the person in the organisation of the path. `fun` returns
  # the answer, or `{:error, words}` for the page of the reports.
  defp with_organisation(conn, %{"organisation" => short_name}, fun) do
    with %{} = user <- conn.assigns[:current_user],
         {:ok, organisation, _member} <- Accounts.organisation_for(user, short_name) do
      case fun.(organisation, actor: user, tenant: organisation) do
        %Plug.Conn{} = conn -> conn
        {:error, words} when is_binary(words) -> back(conn, organisation, words)
      end
    else
      _no -> not_found(conn)
    end
  end

  # The same for a report of one resident, which the person must read.
  defp with_resident(conn, %{"id" => id} = params, fun) when is_binary(id) do
    with_organisation(conn, params, fn organisation, options ->
      with {:ok, _uuid} <- Ecto.UUID.cast(id),
           {:ok, %{} = resident} <- Residents.resident(id, [load: [:name]] ++ options) do
        fun.(resident, organisation, options)
      else
        _no_resident -> not_found(conn)
      end
    end)
  end

  defp with_resident(conn, _params, _fun), do: not_found(conn)

  defp answer({:ok, %AshTypst.Document{format: :pdf, data: pdf}}, conn, _organisation, name) do
    conn
    |> put_resp_content_type("application/pdf", nil)
    |> put_resp_header("cache-control", "private, no-store")
    |> put_resp_header("content-disposition", ~s(inline; filename="#{name}"))
    |> send_resp(200, pdf)
  end

  defp answer({:error, error}, conn, organisation, _name) do
    case Reports.reason(error) do
      :too_many ->
        conn
        |> put_resp_content_type("text/plain")
        |> put_resp_header("retry-after", "60")
        |> send_resp(429, "You made many reports in a short time. Wait a minute, then try again.")

      {:invalid, field, words} ->
        back(conn, organisation, "#{day_of(field)} #{words}.")

      reason when reason in [:forbidden, :not_found] ->
        not_found(conn)

      :fault when is_exception(error) ->
        raise error

      :fault ->
        raise "A report failed: #{inspect(error)}"
    end
  end

  # The name of the day that an argument holds, to start a sentence.
  defp day_of(:from), do: "The first day"
  defp day_of(:to), do: "The last day"
  defp day_of(_on), do: "The day"

  # A date of a form: none, a date, or words.
  defp date(nil), do: {:ok, nil}
  defp date(""), do: {:ok, nil}

  defp date(text) when is_binary(text) do
    case Date.from_iso8601(text) do
      {:ok, date} -> {:ok, date}
      {:error, _not_a_date} -> {:error, "Give a date as a day, a month and a year."}
    end
  end

  defp date(_other), do: {:error, "Give a date as a day, a month and a year."}

  # The paper that the address names, as an argument of a report, or no
  # argument: then the document is on the paper of the organisation.
  defp paper(%{"paper" => text}) do
    case Accounts.paper_size(text) do
      nil -> %{}
      paper -> %{paper: paper}
    end
  end

  defp paper(_params), do: %{}

  defp journal("all"), do: :all
  defp journal("none"), do: :none
  defp journal(_medical), do: :medical

  # The day in the name of a file: the one of the report, or today.
  defp day(%Date{} = date, _organisation), do: Date.to_iso8601(date)
  defp day(nil, organisation), do: Date.to_iso8601(Accounts.today(organisation))

  # The name that a browser saves a report of a resident under: the name of
  # the resident in plain letters, the report, and the day.
  defp file_name(resident, report, organisation) do
    plain =
      (resident.name || "")
      |> String.normalize(:nfd)
      |> String.replace(~r/[^A-Za-z0-9]+/, "-")
      |> String.trim("-")
      |> String.downcase()
      |> String.slice(0, 40)

    name = if plain == "", do: "resident", else: plain
    "#{name}-#{report}-#{day(nil, organisation)}.pdf"
  end

  defp back(conn, organisation, words) do
    conn
    |> put_flash(:error, words)
    |> redirect(to: ~p"/o/#{organisation.short_name}/reports")
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(html: RescordWeb.ErrorHTML)
    |> render(:"404")
  end
end
