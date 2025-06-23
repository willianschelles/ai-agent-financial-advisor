#!/bin/bash
# Render build script for Elixir Phoenix applications

set -e

export MIX_ENV=prod

# Initial setup
echo "Setting up Elixir..."
export LANG=en_US.UTF-8
export ERL_AFLAGS="-kernel shell_history enabled"

# Install dependencies
echo "Installing dependencies..."
mix local.hex --force
mix local.rebar --force
mix deps.get --only prod

# Compile the project
echo "Compiling project..."
mix compile

# Deploy assets
echo "Deploying assets..."
mix assets.deploy

# Run database migrations
echo "Migration will be run after release during application startup..."

# Create release
echo "Creating release..."
mix release --overwrite

# Create a directory for the release scripts
mkdir -p _build/prod/rel/ai_agent/bin

# Create a server script to run the application
cat > _build/prod/rel/ai_agent/bin/server << 'EOF'
#!/bin/sh
# Run migrations before starting the app
/app/bin/migrate
exec /app/bin/ai_agent start
EOF

# Create a migration script
cat > _build/prod/rel/ai_agent/bin/migrate << 'EOF'
#!/bin/sh
exec /app/bin/ai_agent eval "AiAgent.Release.migrate"
EOF

# Make the scripts executable
chmod +x _build/prod/rel/ai_agent/bin/server
chmod +x _build/prod/rel/ai_agent/bin/migrate

echo "Build completed successfully!"
