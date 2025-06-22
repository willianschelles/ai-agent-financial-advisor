defmodule AiAgentWeb.Router do
  use AiAgentWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:fetch_flash)

    plug(:put_root_layout, html: {AiAgentWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", AiAgentWeb do
    pipe_through(:browser)

    get("/", PageController, :home)
    get("/login", LoginController, :index)
    delete("/logout", AuthController, :logout)
  end

  scope "/", AiAgentWeb do
    pipe_through([:browser, :browser_auth])

    live("/chat", ChatLive)
  end

  # /auth/google or /auth/hubspot
  scope "/auth", AiAgentWeb do
    pipe_through([:browser, :browser_auth])

    get("/:provider", AuthController, :request)
    get("/:provider/callback", AuthController, :callback)
  end

  pipeline :browser_auth do
    plug(:fetch_session)
    plug(AiAgentWeb.Plugs.Auth)
  end

  # Other scopes may use custom stacks.
  # scope "/api", AiAgentWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:ai_agent, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: AiAgentWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
