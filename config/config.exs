# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ai_agent,
  ecto_repos: [AiAgent.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure pgvector
config :ai_agent, AiAgent.Repo, types: AiAgent.PostgresTypes

# Configures the endpoint
config :ai_agent, AiAgentWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AiAgentWeb.ErrorHTML, json: AiAgentWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AiAgent.PubSub,
  live_view: [signing_salt: "LTL1uBk2"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :ai_agent, AiAgent.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  ai_agent: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  ai_agent: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

## AI agentic specifics
config :ai_agent, Oban,
  repo: AiAgent.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [default: 10]

# OAuth
config :ueberauth, Ueberauth,
  providers: [
    google: {
      Ueberauth.Strategy.Google,
      [
        default_scope:
          "email profile https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.send https://www.googleapis.com/auth/pubsub https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/gmail.compose https://mail.google.com/ https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/gmail.insert"
      ]
    },
    hubspot: {
      HubspotAuth.HubspotStrategy,
      [
        oauth2_module: HubspotAuth.HubspotOAuth
        # Add any other strategy options here
      ]
      # [
      #   client_id: System.get_env("HUBSPOT_CLIENT_ID"),
      #   client_secret: System.get_env("HUBSPOT_CLIENT_SECRET"),
      #   redirect_uri:
      #     System.get_env("HUBSPOT_REDIRECT_URI") || "http://localhost:4000/auth/hubspot/callback",
      #   default_scope: "oauth crm.objects.contacts.read crm.objects.contacts.write"
      # ]
    }
  ]

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

config :ueberauth, HubspotAuth.HubspotOAuth,
  client_id: System.get_env("HUBSPOT_CLIENT_ID"),
  client_secret: System.get_env("HUBSPOT_CLIENT_SECRET"),
  redirect_uri: System.get_env("HUBSPOT_REDIRECT_URI") ||
                   "http://localhost:4000/auth/hubspot/callback",
  site: "https://api.hubapi.com",
  authorize_url: "https://app.hubspot.com/oauth/authorize",
  token_url: "https://api.hubapi.com/oauth/v1/token"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
