# Step 11 - Bootstrap

# Create a new Phoenix LiveView project with Postgres
mix phx.new ai_agent --live --database postgres
cd ai_agent

# Install dependencies
mix deps.get

# Create and migrate the database
mix ecto.create
mix ecto.migrate

# Create `User` schema + migration
mix phx.gen.schema User users email:string google_tokens:m

# Create a new Phoenix LiveView project with Postgres
mix phx.new ai_agent --live --database postgres
cd ai_agent

# Install dependencies
mix deps.get

# Create and migrate the database
mix ecto.create
mix ecto.migrate

# Create `User` schema + migration
mix phx.gen.schema User users email:string google_tokens:map hubspot_tokens:map

# Create `Document` schema + migration
mix phx.gen.schema Document documents user_id:references:users type:string source:string content:text embedding:vector:1536

# Create `Memory` schema + migration
mix phx.gen.schema Memory memories user_id:references:users instruction:text

# Add Oban for background jobs to mix.exs
# Add inside deps:
# {:oban, "~> 2.17"},

# Configure Oban in config/config.exs
config :ai_agent, Oban,
  repo: AiAgent.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [default: 10]

# Add pgvector extension support
# (after installing pgvector in Postgres)
mix ecto.gen.migration add_pgvector_extension
# In generated file:
def change do
  execute "CREATE EXTENSION IF NOT EXISTS vector"
end

mix ecto.migrate

# Enable session plug and LiveView root layout in endpoint.ex
# Also prepare router.ex to support /chat route and /auth paths.

# Run the dev server
mix phx.server