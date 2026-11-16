defmodule RescordWeb.Router do
  use RescordWeb, :router

  import RescordWeb.UserAuth, only: [fetch_current_user: 2]

  # In the tests only: a LiveView of a browser test uses the database
  # transaction of that test (ADR 0023). This hook is the first one of each
  # live session, because the hook after it reads the database.
  @sandbox_hooks (if Application.compile_env(:rescord, :sql_sandbox) do
                    [RescordWeb.LiveSandbox]
                  else
                    []
                  end)

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RescordWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", RescordWeb do
    pipe_through :browser

    get "/", PageController, :home

    # The sign-in by a link in an email (ADR 0018).
    get "/sign-in", SignInController, :new
    post "/sign-in", SignInController, :create
    get "/sign-in/sent", SignInController, :sent
    get "/sign-in/link", SignInController, :link
    post "/sign-in/link", SignInController, :confirm
    delete "/sign-out", SignInController, :delete

    # The pages of a root user.
    live_session :root, on_mount: @sandbox_hooks ++ [{RescordWeb.UserAuth, :require_root}] do
      live "/root", RootLive
      live "/root/lists", ListsLive, :shared
    end

    # The pages of one organisation, which the path names (ADR 0011).
    live_session :organisation,
      on_mount: @sandbox_hooks ++ [{RescordWeb.UserAuth, :require_organisation}] do
      live "/o/:organisation", OrganisationLive
      live "/o/:organisation/members", MembersLive
      live "/o/:organisation/settings", SettingsLive
      live "/o/:organisation/lists", ListsLive, :organisation
      live "/o/:organisation/tasks", TasksLive
      live "/o/:organisation/routines", RoutinesLive, :index
      live "/o/:organisation/routines/:id/edit", RoutinesLive, :edit
      live "/o/:organisation/housing", HousingLive
      live "/o/:organisation/housing/:id", LocationLive
      live "/o/:organisation/groups", GroupsLive
      live "/o/:organisation/groups/:id", GroupLive
      live "/o/:organisation/residents", ResidentsLive
      live "/o/:organisation/residents/new", ResidentFormLive, :new
      live "/o/:organisation/residents/:id", ResidentLive
      live "/o/:organisation/residents/:id/edit", ResidentFormLive, :edit
      live "/o/:organisation/residents/:id/journal", JournalLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", RescordWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:rescord, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: RescordWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
