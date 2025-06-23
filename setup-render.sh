#!/bin/bash
# Setup script for deploying to Render

set -e

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}==== AI Agent Financial Advisor - Render Setup ====${NC}"
echo "This script will prepare your application for deployment to Render."

# Check if required files exist
echo -e "${YELLOW}Checking for required files...${NC}"

if [ ! -f "render.yaml" ]; then
  echo -e "${RED}render.yaml not found!${NC}"
  exit 1
fi

if [ ! -f "render-build.sh" ]; then
  echo -e "${RED}render-build.sh not found!${NC}"
  exit 1
fi

# Make the build script executable
echo -e "${YELLOW}Making render-build.sh executable...${NC}"
chmod +x render-build.sh

# Check if the health check controller exists
if [ ! -f "lib/ai_agent_web/controllers/health_controller.ex" ]; then
  echo -e "${RED}Health controller not found!${NC}"
  echo "Please make sure you have created lib/ai_agent_web/controllers/health_controller.ex"
  exit 1
fi

# Check if the release module exists
if [ ! -f "lib/ai_agent/release.ex" ]; then
  echo -e "${RED}Release module not found!${NC}"
  echo "Please make sure you have created lib/ai_agent/release.ex"
  exit 1
fi

# Generate a secret key base if needed
echo -e "${YELLOW}Generating a SECRET_KEY_BASE for you to use...${NC}"
SECRET_KEY_BASE=$(mix phx.gen.secret)
echo -e "${GREEN}Generated SECRET_KEY_BASE:${NC} $SECRET_KEY_BASE"
echo "You will need to set this as an environment variable in your Render dashboard."

# Ensure PGVector extension is setup in config
echo -e "${YELLOW}Checking PGVector configuration...${NC}"
if grep -q "pgvector" config/config.exs; then
  echo -e "${GREEN}PGVector configuration found in config/config.exs${NC}"
else
  echo -e "${RED}Warning: PGVector configuration not found!${NC}"
  echo "Please ensure you have configured pgvector in your config files."
fi

# Final instructions
echo -e "\n${GREEN}==== Setup Complete ====${NC}"
echo -e "To deploy to Render:"
echo -e "1. Push your code to a Git repository"
echo -e "2. Connect your repository to Render"
echo -e "3. Render will detect your render.yaml and create the necessary services"
echo -e "4. Set the following environment variables in your Render dashboard:"
echo -e "   - SECRET_KEY_BASE: $SECRET_KEY_BASE"
echo -e "   - GOOGLE_CLIENT_ID: your-google-client-id"
echo -e "   - GOOGLE_CLIENT_SECRET: your-google-client-secret"
echo -e "   - HUBSPOT_CLIENT_ID: your-hubspot-client-id"
echo -e "   - HUBSPOT_CLIENT_SECRET: your-hubspot-client-secret"
echo -e "   - OPENAI_API_KEY: your-openai-api-key"
echo -e "5. Update your OAuth redirect URIs to point to your Render app URL"
echo -e "\nSee RENDER_DEPLOYMENT.md for more detailed instructions."
