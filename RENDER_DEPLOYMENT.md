# Deploying AI Agent Financial Advisor to Render

This guide walks through deploying the AI Agent Financial Advisor application to [Render](https://render.com).

## Prerequisites

- A Render account
- Git repository with your application code
- OpenAI API key
- Google OAuth credentials
- Hubspot OAuth credentials

## Deployment Files

The following files have been created to support Render deployment:

1. `render.yaml` - Defines the services and database
2. `render-build.sh` - Build script for the Elixir/Phoenix application
3. `lib/ai_agent_web/controllers/health_controller.ex` - Health check endpoint
4. `lib/ai_agent/release.ex` - Database migration support

## Deployment Steps

### 1. Push Your Code to a Git Repository

Make sure your code is in a Git repository (GitHub, GitLab, etc.) that Render can access.

### 2. Create a New Web Service in Render

1. Log in to your Render dashboard
2. Click "New" and select "Blueprint"
3. Connect your Git repository
4. Render will automatically detect the `render.yaml` configuration
5. Click "Apply" to create the defined services

Alternatively, you can manually create the services:

1. Click "New" and select "Web Service"
2. Connect your Git repository
3. Name: `ai-agent-financial-advisor`
4. Environment: `Elixir`
5. Build Command: `./render-build.sh`
6. Start Command: `_build/prod/rel/ai_agent/bin/server`

### 3. Configure Environment Variables

If not using the Blueprint approach, you'll need to set these environment variables manually:

- `MIX_ENV`: `prod`
- `PORT`: `8080`
- `SECRET_KEY_BASE`: Generate with `mix phx.gen.secret`
- `DATABASE_URL`: Automatically set if using Render PostgreSQL
- `GOOGLE_CLIENT_ID`: Your Google OAuth client ID
- `GOOGLE_CLIENT_SECRET`: Your Google OAuth client secret
- `HUBSPOT_CLIENT_ID`: Your Hubspot client ID
- `HUBSPOT_CLIENT_SECRET`: Your Hubspot client secret
- `OPENAI_API_KEY`: Your OpenAI API key

### 4. Create a PostgreSQL Database

If not using the Blueprint approach:

1. Click "New" and select "PostgreSQL"
2. Name: `ai-agent-database`
3. PostgreSQL Version: 15
4. After creation, note the "Internal Database URL"

### 5. Enable pgvector Extension

Connect to your database via the Render shell and run:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

### 6. Update OAuth Redirect URIs

Update your Google and Hubspot OAuth configurations with your Render app URL:

- Google: `https://your-app-name.onrender.com/auth/google/callback`
- Hubspot: `https://your-app-name.onrender.com/auth/hubspot/callback`

### 7. Deploy Your Application

Render will automatically deploy your application when you push changes to your repository's main branch.

You can also manually trigger a deployment from the Render dashboard.

## Monitoring and Maintenance

- **Logs**: Access logs from the Render dashboard
- **Metrics**: Monitor CPU and memory usage in the Render dashboard
- **Database**: Access your database through the Render shell

## Troubleshooting

1. **Database Connection Issues**:
   - Check the DATABASE_URL environment variable
   - Ensure the pgvector extension is installed
   - Verify database permissions

2. **Build Failures**:
   - Check build logs in the Render dashboard
   - Ensure render-build.sh is executable (`git update-index --chmod=+x render-build.sh`)

3. **OAuth Issues**:
   - Verify redirect URIs are correct
   - Check that environment variables for OAuth credentials are set correctly

4. **Application Errors**:
   - Check application logs in the Render dashboard
   - Try restarting the web service

## Scaling

To scale your application on Render:

1. Go to your web service in the Render dashboard
2. Select "Settings"
3. Under "Instance Type", choose a plan with more resources
4. For horizontal scaling, you can enable autoscaling in paid plans