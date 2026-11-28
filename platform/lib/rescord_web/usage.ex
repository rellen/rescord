defmodule RescordWeb.Usage do
  @moduledoc """
  Counts the pages that open and the files that Rescord sends, for the
  usage counts (ADR 0098), from the `:telemetry` events of Phoenix:

  - `[:phoenix, :live_view, :mount, :stop]`: a page that connected. A page
    mounts two times, for the first answer and for the live connection,
    and only the second one counts. The item is the name of the module,
    such as `expense_form` for `RescordWeb.ExpenseFormLive`.
  - `[:phoenix, :router_dispatch, :stop]`: a request that a controller of a
    file answered with a status 2xx: a report as PDF, the CSV file of the
    expenses, the export, a transfer file, a calendar feed.

  Each page and each file route maps to a feature of
  `Rescord.Usage.Features`, here. `RescordWeb.UsageTest` fails for a page
  or a route with no feature and no reason to leave it out, so a count
  never has a key that a browser sent.

  The sign-in, the health check, the pictures of a page and the files of a
  record are not counted: the page that shows them counts.
  """

  alias Rescord.Usage

  @handler "rescord-usage-web"

  # The feature of each page.
  @pages %{
    RescordWeb.OrganisationLive => :organisation,
    RescordWeb.ResidentsLive => :residents,
    RescordWeb.ResidentLive => :residents,
    RescordWeb.ResidentFormLive => :residents,
    RescordWeb.GroupsLive => :groups,
    RescordWeb.GroupLive => :groups,
    RescordWeb.HousingLive => :housing,
    RescordWeb.LocationLive => :housing,
    RescordWeb.JournalLive => :journal,
    RescordWeb.ConditionsLive => :conditions,
    RescordWeb.MeasurementsLive => :measurements,
    RescordWeb.GroupMeasurementsLive => :measurements,
    RescordWeb.TimelineLive => :timeline,
    RescordWeb.PhotosLive => :photos,
    RescordWeb.TasksLive => :tasks,
    RescordWeb.TaskLive => :tasks,
    RescordWeb.NotificationsLive => :notifications,
    RescordWeb.RoutinesLive => :routines,
    RescordWeb.CalendarLive => :calendar,
    RescordWeb.InventoryLive => :inventory,
    RescordWeb.ItemLive => :inventory,
    RescordWeb.SuppliersLive => :inventory,
    RescordWeb.ExpensesLive => :expenses,
    RescordWeb.ExpenseLive => :expenses,
    RescordWeb.ExpenseFormLive => :expenses,
    RescordWeb.ReportsLive => :reports,
    RescordWeb.CareInsightsLive => :reports,
    RescordWeb.ResidentsInsightsLive => :reports,
    RescordWeb.ConditionsInsightsLive => :reports,
    RescordWeb.TransfersLive => :transfers,
    RescordWeb.PartnersLive => :transfers,
    RescordWeb.ExportLive => :export,
    RescordWeb.ToolsLive => :tools,
    RescordWeb.DoseLive => :tools,
    RescordWeb.RubySettingsLive => :assistant,
    RescordWeb.RubyLive => :assistant,
    RescordWeb.RubyConversationsLive => :assistant,
    RescordWeb.ListsLive => :lists,
    RescordWeb.MembersLive => :members,
    RescordWeb.RolesLive => :members,
    RescordWeb.PrivacyLive => :members,
    RescordWeb.PrivacyRequestLive => :members,
    RescordWeb.SettingsLive => :settings,
    RescordWeb.RootLive => :server,
    RescordWeb.RootRubyLive => :server,
    RescordWeb.RootUsageLive => :server,
    RescordWeb.RootPushLive => :server,
    RescordWeb.RootPrivacyLive => :server,
    RescordWeb.RootScanLive => :server,
    RescordWeb.RootHealthLive => :server
  }

  # The feature and the item of each file, by the controller and its action.
  @files %{
    {RescordWeb.ReportController, :resident_record} => {:reports, "reports.resident_record"},
    {RescordWeb.ReportController, :cage_card} => {:reports, "reports.cage_card"},
    {RescordWeb.ReportController, :register} => {:reports, "reports.register"},
    {RescordWeb.ReportController, :movements} => {:reports, "reports.movements"},
    {RescordWeb.ReportController, :task_sheet} => {:reports, "reports.task_sheet"},
    {RescordWeb.ReportController, :stock} => {:reports, "reports.stock"},
    {RescordWeb.ReportController, :housing} => {:reports, "reports.housing"},
    {RescordWeb.ReportController, :expenses} => {:reports, "reports.expenses"},
    {RescordWeb.ExpenseFileController, :index} => {:expenses, "expenses.csv"},
    {RescordWeb.ExportController, :create} => {:export, "export.archive"},
    {RescordWeb.TransferFileController, :export} => {:transfers, "transfers.export"},
    {RescordWeb.TransferFileController, :show} => {:transfers, "transfers.file"},
    {RescordWeb.CalendarFeedController, :show} => {:calendar, "calendar.feed"}
  }

  # The controllers that are not counted, with the reason.
  @not_counted %{
    RescordWeb.HealthController => "the health check of the server",
    RescordWeb.PageController => "the first page and the colophon, before a sign-in",
    RescordWeb.PrivacyNoticeController => "the privacy notices, read with no sign-in",
    RescordWeb.SignInController => "the sign-in: it says who works, and when",
    RescordWeb.AttachmentController => "a file of a record: the page that links it counts",
    RescordWeb.PhotoController => "the pictures of a page",
    RescordWeb.ReceiptController => "a file of a record: the page that links it counts",
    RescordWeb.MailPreviewController => "the emails in development",
    RescordWeb.CatalogueController => "the catalogue of the components, in development",
    Oban.Web.Assets => "the stylesheet, the script and the font of Oban Web (ADR 0110)"
  }

  @doc "Starts to listen to the pages and the requests. A second call changes nothing."
  @spec attach() :: :ok
  def attach do
    events = [[:phoenix, :live_view, :mount, :stop], [:phoenix, :router_dispatch, :stop]]

    case :telemetry.attach_many(@handler, events, &__MODULE__.handle/4, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc false
  def handle([:phoenix, :live_view, :mount, :stop], _measurements, %{socket: socket}, _config) do
    with true <- Phoenix.LiveView.connected?(socket),
         {:ok, feature} <- Map.fetch(@pages, socket.view) do
      Usage.count(feature, :page, item(socket.view))
    end

    :ok
  end

  def handle([:phoenix, :router_dispatch, :stop], _measurements, metadata, _config) do
    with %{conn: %Plug.Conn{status: status}, plug: plug, plug_opts: action}
         when status in 200..299 <- metadata,
         {:ok, {feature, item}} <- Map.fetch(@files, {plug, action}) do
      Usage.count(feature, :file, item)
    end

    :ok
  end

  def handle(_event, _measurements, _metadata, _config), do: :ok

  @doc "The item of a page: the name of its module, with no `Live`."
  @spec item(module) :: String.t()
  def item(view) do
    view
    |> Module.split()
    |> List.last()
    |> String.replace_suffix("Live", "")
    |> Macro.underscore()
  end

  @doc "The feature of each page, by its module."
  @spec pages() :: %{module => atom}
  def pages, do: @pages

  @doc "The feature and the item of each file, by `{controller, action}`."
  @spec files() :: %{{module, atom} => {atom, String.t()}}
  def files, do: @files

  @doc "The controllers that are not counted, with the reason."
  @spec not_counted() :: %{module => String.t()}
  def not_counted, do: @not_counted
end
