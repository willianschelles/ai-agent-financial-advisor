# AiAgent

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
# Step 1 Introduction - Structure

# Project: AI Agent for Financial Advisors
# Backend: Elixir (Phoenix LiveView if UI in same stack)
# Frontend (if separate): JS/TS (e.g., Next.js or plain Phoenix Templates)
# LLM: OpenAI GPT-4o or GPT-4.5 via OpenAI API
# Vector Store: pgvector
# DB: PostgreSQL
# Deployment: Fly.io or Render

# Step-by-step scaffolding, major components

# --- 1. Mix Project Setup ---
mix phx.new ai_agent --no-ecto --live
cd ai_agent

# Add dependencies to mix.exs
# mix.exs
{:finch, "~> 0.16"},
{:req, ">= 0.0.0"},
{:openai, "~> 0.6.0"}, # hex package for OpenAI API
{:plug_oauth2, github: "scrogson/oauth2"},
{:pgvector, "~> 0.2.0"},
{:ecto_sql, "~> 3.10"},
{:postgrex, ">= 0.0.0"},
{:oban, "~> 2.15"}, # for tasks
{:jason, "~> 1.4"},

# --- 2. OAuth Setup ---
# Google and Hubspot OAuth2 using custom strategy (or plug_oauth2)
# Use Ueberauth optionally if preferred.
# You will need to:
# - Register Google OAuth app (gmail, calendar scopes)
# - Register Hubspot developer app
# - Add test user (webshookeng@gmail.com)

# Routes (router.ex)
scope "/auth" do
  get "/google", OAuth.GoogleController, :request
  get "/google/callback", OAuth.GoogleController, :callback
  get "/hubspot", OAuth.HubspotController, :request
  get "/hubspot/callback", OAuth.HubspotController, :callback
end

# Controllers will handle token exchanges and store tokens in DB

# --- 3. Chat UI ---
# Use LiveView or add API if client is external
# Main chat interface (ChatLive)
# Send messages to backend: {:chat, user_input}
# Use memory and RAG to answer questions and take actions

# --- 4. Embeddings and RAG Setup ---
# Emails + Hubspot notes => Embed and store in Postgres with pgvector
# lib/ai_agent/embeddings/vector_store.ex
# Schema: documents (id, source, type, content, embedding)
# Use OpenAI embeddings endpoint to generate vectors

# --- 5. Tool Calling ---
# Define tool schemas for each capability (schedule, email, crm_update, etc.)
# JSON schema-based tool descriptions for LLM
# When user prompt needs tool use, LLM should return structured call

# --- 6. Memory and Ongoing Instructions ---
# Store per-user memory in DB (table: memories)
# Format: %{user_id, instruction, inserted_at}
# At each event (email, hubspot, calendar), query memory and feed as system prompt

# --- 7. Background Jobs ---
# Use Oban for async job execution (e.g., wait for email replies)
# Schedule polling if no webhook

# --- 8. Webhooks or Polling ---
# Set up Gmail, Calendar, Hubspot webhooks to receive activity
# On each event:
# - Enrich with context
# - RAG + memory => decide if an action is needed
# - Tool call if needed

# --- 9. LLM Agent Module ---
# lib/ai_agent/llm_agent.ex
# def chat(user, message) do
#   context = RAG.load(user)
#   memory = Memory.load(user)
#   prompt = AgentPrompt.build(message, context, memory)
#   OpenAI.chat(prompt, tools)
# end

# --- 10. Deployment ---
# Deploy to Fly.io or Render
# Use env vars for secrets (OpenAI key, OAuth secrets)
# Enable HTTPS for secure OAuth

# --- Sample Tool JSON ---
# ScheduleMeeting
%{
  name: "schedule_meeting",
  description: "Schedule a meeting with a contact",
  parameters: %{
    type: "object",
    properties: %{
      contact_name: %{type: "string"},
      times: %{type: "array", items: %{type: "string"}},
    },
    required: ["contact_name", "times"]
  }
}

# --- Final Notes ---
# Focus areas for MVP:
# 1. Working Gmail + Hubspot OAuth
# 2. Ingest + embed email + notes (RAG)
# 3. Simple chat interface with OpenAI tool calling
# 4. One proactive memory-triggered action
#
# Then iterate with more tool functions + ongoing memory usage



# Step 2 project structure - and schema definition
# File structure
# ├── lib/
# │   ├── ai_agent/
# │   │   ├── application.ex
# │   │   ├── web/
# │   │   │   ├── router.ex
# │   │   │   ├── controllers/
# │   │   │   │   ├── oauth_controller.ex
# │   │   │   ├── live/
# │   │   │   │   ├── chat_live.ex
# │   │   ├── auth/
# │   │   │   ├── google_oauth.ex
# │   │   │   ├── hubspot_oauth.ex
# │   │   ├── llm/
# │   │   │   ├── agent.ex
# │   │   │   ├── embeddings.ex
# │   │   │   ├── tools.ex
# │   │   ├── context/
# │   │   │   ├── users.ex
# │   │   │   ├── chat.ex
# │   │   ├── schemas/
# │   │   │   ├── user.ex
# │   │   │   ├── memory.ex
# │   │   │   ├── document.ex

# Router (router.ex)
scope "/auth", AiAgentWeb do
  get "/google", OauthController, :google_request
  get "/google/callback", OauthController, :google_callback
  get "/hubspot", OauthController, :hubspot_request
  get "/hubspot/callback", OauthController, :hubspot_callback
end

scope "/", AiAgentWeb do
  pipe_through :browser
  live "/chat", ChatLive, :index
end

# Controller (oauth_controller.ex)
defmodule AiAgentWeb.OauthController do
  use AiAgentWeb, :controller
  alias AiAgent.Auth.{GoogleOAuth, HubspotOAuth}

  def google_request(conn, _params), do: redirect(conn, external: GoogleOAuth.auth_url())
  def google_callback(conn, params), do: GoogleOAuth.handle_callback(conn, params)

  def hubspot_request(conn, _params), do: redirect(conn, external: HubspotOAuth.auth_url())
  def hubspot_callback(conn, params), do: HubspotOAuth.handle_callback(conn, params)
end

# LiveView (chat_live.ex)
defmodule AiAgentWeb.ChatLive do
  use Phoenix.LiveView
  alias AiAgent.Context.Chat

  def mount(_params, _session, socket) do
    {:ok, assign(socket, query: "", response: nil)}
  end

  def handle_event("submit", %{"query" => query}, socket) do
    response = Chat.ask(socket.assigns.current_user, query)
    {:noreply, assign(socket, response: response)}
  end
end

# Context (chat.ex)
defmodule AiAgent.Context.Chat do
  alias AiAgent.LLM.Agent
  def ask(user, question), do: Agent.chat(user, question)
end

# OAuth Modules (google_oauth.ex and hubspot_oauth.ex)
defmodule AiAgent.Auth.GoogleOAuth do
  def auth_url do
    # Construct URL with scopes: email, gmail.readonly, calendar
  end
  def handle_callback(conn, %{"code" => code}) do
    # Exchange code for tokens, store them in DB
  end
end

defmodule AiAgent.Auth.HubspotOAuth do
  def auth_url do
    # Construct URL with scopes
  end
  def handle_callback(conn, %{"code" => code}) do
    # Exchange code for access_token
  end
end

# LLM Agent (agent.ex)
defmodule AiAgent.LLM.Agent do
  def chat(user, message) do
    context = RAG.load(user)
    memory = Memory.load(user)
    tools = Tools.list()
    prompt = PromptBuilder.build(message, context, memory)
    OpenAI.Chat.call(prompt, tools)
  end
end

# Schema (user.ex)
defmodule AiAgent.Schemas.User do
  use Ecto.Schema
  schema "users" do
    field :email, :string
    field :google_tokens, :map
    field :hubspot_tokens, :map
    timestamps()
  end
end

# Schema (memory.ex)
defmodule AiAgent.Schemas.Memory do
  use Ecto.Schema
  schema "memories" do
    field :instruction, :string
    belongs_to :user, AiAgent.Schemas.User
    timestamps()
  end
end

# Schema (document.ex)
defmodule AiAgent.Schemas.Document do
  use Ecto.Schema
  schema "documents" do
    field :source, :string
    field :type, :string
    field :content, :string
    field :embedding, Pgvector.Ecto.Vector
    timestamps()
  end
end



# Step 3 - Full OAuth, RAG embedding retriavel using  OpenAI _+ pgvector and Tool calling
# --- GoogleOAuth Logic ---
defmodule AiAgent.Auth.GoogleOAuth do
  @client_id System.get_env("GOOGLE_CLIENT_ID")
  @client_secret System.get_env("GOOGLE_CLIENT_SECRET")
  @redirect_uri System.get_env("GOOGLE_REDIRECT_URI")

  def auth_url do
    URI.encode("https://accounts.google.com/o/oauth2/v2/auth?" <>
      URI.encode_query(%{
        client_id: @client_id,
        redirect_uri: @redirect_uri,
        response_type: "code",
        scope: "https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/calendar.events",
        access_type: "offline",
        prompt: "consent"
      }))
  end

  def handle_callback(conn, %{"code" => code}) do
    token_res = Req.post!("https://oauth2.googleapis.com/token", json: %{
      code: code,
      client_id: @client_id,
      client_secret: @client_secret,
      redirect_uri: @redirect_uri,
      grant_type: "authorization_code"
    })

    %{"access_token" => access, "refresh_token" => refresh} = token_res.body
    email = fetch_user_email(access)
    user = AiAgent.Context.Users.upsert_google_user(email, %{access: access, refresh: refresh})
    redirect(conn, to: "/chat")
  end

  defp fetch_user_email(access_token) do
    headers = [{"Authorization", "Bearer #{access_token}"}]
    %{body: %{"email" => email}} = Req.get!("https://www.googleapis.com/oauth2/v2/userinfo", headers: headers)
    email
  end
end

# --- HubspotOAuth Logic ---
defmodule AiAgent.Auth.HubspotOAuth do
  @client_id System.get_env("HUBSPOT_CLIENT_ID")
  @client_secret System.get_env("HUBSPOT_CLIENT_SECRET")
  @redirect_uri System.get_env("HUBSPOT_REDIRECT_URI")

  def auth_url do
    "https://app.hubspot.com/oauth/authorize?" <> URI.encode_query(%{
      client_id: @client_id,
      redirect_uri: @redirect_uri,
      scope: "contacts crm.objects.contacts.read crm.objects.contacts.write",
      response_type: "code"
    })
  end

  def handle_callback(conn, %{"code" => code}) do
    token_res = Req.post!("https://api.hubapi.com/oauth/v1/token", 
      headers: [{"Content-Type", "application/x-www-form-urlencoded"}],
      body: URI.encode_query(%{
        grant_type: "authorization_code",
        client_id: @client_id,
        client_secret: @client_secret,
        redirect_uri: @redirect_uri,
        code: code
      })
    )

    %{"access_token" => access_token} = Jason.decode!(token_res.body)
    # link to current user manually for now
    AiAgent.Context.Users.store_hubspot_token("test@example.com", access_token)
    redirect(conn, to: "/chat")
  end
end

# --- Embedding Logic (embeddings.ex) ---
defmodule AiAgent.LLM.Embeddings do
  @openai_key System.get_env("OPENAI_API_KEY")

  def embed(text) do
    headers = [
      {"Authorization", "Bearer #{@openai_key}"},
      {"Content-Type", "application/json"}
    ]

    body = Jason.encode!(%{
      model: "text-embedding-3-small",
      input: text
    })

    %{"data" => [%{"embedding" => vec}]} =
      Req.post!("https://api.openai.com/v1/embeddings", headers: headers, body: body).body

    vec
  end
end

# --- RAG Loader (rag.ex) ---
defmodule AiAgent.LLM.RAG do
  import Ecto.Query
  alias AiAgent.Repo
  alias AiAgent.Schemas.Document

  def load(user) do
    Repo.all(from d in Document, where: d.user_id == ^user.id)
    |> Enum.map(& &1.content)
    |> Enum.join("\n")
  end
end

# --- Tool Definitions (tools.ex) ---
defmodule AiAgent.LLM.Tools do
  def list do
    [
      %{
        name: "schedule_meeting",
        description: "Schedule a meeting with a contact",
        parameters: %{
          type: "object",
          properties: %{
            contact_name: %{type: "string"},
            times: %{type: "array", items: %{type: "string"}}
          },
          required: ["contact_name", "times"]
        }
      },
      %{
        name: "send_email",
        description: "Send an email to a user",
        parameters: %{
          type: "object",
          properties: %{
            to: %{type: "string"},
            subject: %{type: "string"},
            body: %{type: "string"}
          },
          required: ["to", "subject", "body"]
        }
      }
    ]
  end
end


# Step 4 - task memory, webhook handlers, or schedule tool-calling jobs with Oban?
# --- Memory Handling Module ---
defmodule AiAgent.Context.Memory do
  alias AiAgent.Repo
  alias AiAgent.Schemas.Memory

  def store_instruction(user, instruction) do
    %Memory{user_id: user.id, instruction: instruction}
    |> Repo.insert()
  end

  def load(user) do
    Repo.all(from m in Memory, where: m.user_id == ^user.id, select: m.instruction)
  end
end

# --- Webhook Controller Example (webhook_controller.ex) ---
defmodule AiAgentWeb.WebhookController do
  use AiAgentWeb, :controller
  alias AiAgent.Context.Chat

  def gmail(conn, %{"email_data" => data}) do
    # Process email webhook
    user = AiAgent.Context.Users.get_by_email(data["to"])
    Chat.proactive_check(user, %{type: :email, data: data})
    send_resp(conn, 200, "ok")
  end

  def hubspot(conn, %{"event" => event}) do
    # Process Hubspot webhook
    user = AiAgent.Context.Users.get_by_hubspot_id(event["user_id"])
    Chat.proactive_check(user, %{type: :hubspot, data: event})
    send_resp(conn, 200, "ok")
  end

  def calendar(conn, %{"calendar_event" => event}) do
    # Process Google Calendar webhook
    user = AiAgent.Context.Users.get_by_calendar(event["user"])
    Chat.proactive_check(user, %{type: :calendar, data: event})
    send_resp(conn, 200, "ok")
  end
end

# --- Chat Proactive Check Function ---
defmodule AiAgent.Context.Chat do
  alias AiAgent.LLM.Agent
  alias AiAgent.Context.Memory

  def proactive_check(user, input_event) do
    instructions = Memory.load(user)
    prompt = build_proactive_prompt(input_event, instructions)
    Agent.chat(user, prompt)
  end

  defp build_proactive_prompt(event, instructions) do
    """
    You are an AI assistant for a financial advisor. Consider these instructions:
    #{Enum.join(instructions, "\n")}

    This event just happened: #{inspect(event)}
    What should be done?
    """
  end
end

# --- Oban Setup (in application.ex) ---
def start(_type, _args) do
  children = [
    AiAgent.Repo,
    {Oban, oban_config()}
  ]
  Supervisor.start_link(children, strategy: :one_for_one)
end

defp oban_config do
  Application.fetch_env!(:ai_agent, Oban)
end

# --- Oban Job for Tool Execution ---
defmodule AiAgent.Jobs.ToolExecutor do
  use Oban.Worker, queue: :default, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"tool_name" => tool_name, "params" => params}}) do
    case tool_name do
      "send_email" -> AiAgent.Tools.Email.send(params)
      "schedule_meeting" -> AiAgent.Tools.Calendar.schedule(params)
      _ -> :noop
    end
    :ok
  end
end

# --- Example Email Tool Implementation ---
defmodule AiAgent.Tools.Email do
  def send(%{"to" => to, "subject" => subject, "body" => body}) do
    # Use Google API to send email using stored token
    IO.inspect({:sending_email, to, subject, body})
  end
end

# --- Example Calendar Tool Implementation ---
defmodule AiAgent.Tools.Calendar do
  def schedule(%{"contact_name" => name, "times" => times}) do
    # Use Google Calendar API to create event
    IO.inspect({:scheduling_meeting, name, times})
  end
end


# Step 5 PromptBuilder module, implement tool result feedback loops, or set up authentication and user session tracking?

# --- Prompt Builder (prompt_builder.ex) ---
defmodule AiAgent.LLM.PromptBuilder do
  def build(message, context, memory) do
    system = "You are an AI assistant for a financial advisor. Use the context and user instructions to help."
    [
      %{role: "system", content: system},
      %{role: "user", content: "Context:\n#{context}\n\nMemory:\n#{Enum.join(memory, "\n")}"},
      %{role: "user", content: message}
    ]
  end
end

# --- Tool Feedback Integration (agent.ex) ---
defmodule AiAgent.LLM.Agent do
  alias AiAgent.LLM.{RAG, Memory, Tools, PromptBuilder}
  alias AiAgent.Jobs.ToolExecutor
  alias Oban

  def chat(user, message) do
    context = RAG.load(user)
    memory = Memory.load(user)
    tools = Tools.list()
    prompt = PromptBuilder.build(message, context, memory)

    response = OpenAI.Chat.call(%{
      model: "gpt-4o",
      messages: prompt,
      tools: tools,
      tool_choice: "auto"
    })

    handle_response(user, response)
  end

  defp handle_response(user, %{"tool_calls" => calls}) do
    Enum.each(calls, fn %{"function" => %{"name" => name, "arguments" => args}} ->
      Oban.insert!(ToolExecutor.new(%{"tool_name" => name, "params" => Jason.decode!(args)}))
    end)
    "Tool call initiated."
  end

  defp handle_response(_user, %{"choices" => [%{"message" => %{"content" => text}}]}), do: text
end

# --- Authentication Plug (auth_plug.ex) ---
defmodule AiAgentWeb.Plugs.Auth do
  import Plug.Conn
  alias AiAgent.Context.Users

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :user_id) do
      nil ->
        conn
        |> Phoenix.Controller.redirect(to: "/auth/google")
        |> halt()
      user_id ->
        assign(conn, :current_user, Users.get!(user_id))
    end
  end
end

# --- Apply Plug in Router ---
# router.ex
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_flash
  plug AiAgentWeb.Plugs.Auth
end

# --- Users Context ---
defmodule AiAgent.Context.Users do
  alias AiAgent.Repo
  alias AiAgent.Schemas.User

  def upsert_google_user(email, tokens) do
    case Repo.get_by(User, email: email) do
      nil -> %User{email: email, google_tokens: tokens} |> Repo.insert!()
      user -> Repo.update!(User.changeset(user, %{google_tokens: tokens}))
    end
  end

  def store_hubspot_token(email, token) do
    user = Repo.get_by(User, email: email)
    Repo.update!(User.changeset(user, %{hubspot_tokens: token}))
  end

  def get!(id), do: Repo.get!(User, id)
  def get_by_email(email), do: Repo.get_by(User, email: email)
end

# --- User Changeset ---
defmodule AiAgent.Schemas.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :google_tokens, :map
    field :hubspot_tokens, :map
    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :google_tokens, :hubspot_tokens])
    |> validate_required([:email])
  end
end


# step 6 frontend login flow with Google session handling, build a LiveView chat interface, or test a full end-to-end tool execution flow?
# --- LiveView Chat UI (chat_live.ex) ---
defmodule AiAgentWeb.ChatLive do
  use AiAgentWeb, :live_view
  alias AiAgent.Context.Chat

  def mount(_params, session, socket) do
    user = AiAgent.Context.Users.get!(session["user_id"])
    {:ok, assign(socket, query: "", response: nil, current_user: user)}
  end

  def handle_event("submit", %{"query" => query}, socket) do
    response = Chat.ask(socket.assigns.current_user, query)
    {:noreply, assign(socket, response: response, query: "")}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto mt-10">
      <h1 class="text-2xl font-bold mb-4">Financial Agent Chat</h1>

      <form phx-submit="submit">
        <input type="text" name="query" value={@query} placeholder="Ask me anything..."
               class="w-full p-2 border rounded mb-2"/>
        <button type="submit" class="px-4 py-2 bg-blue-600 text-white rounded">Send</button>
      </form>

      <div class="mt-4">
        <h2 class="text-lg font-semibold">Response:</h2>
        <p><%= @response %></p>
      </div>
    </div>
    """
  end
end

# --- Login UI (auth_view.ex) ---
defmodule AiAgentWeb.AuthView do
  use AiAgentWeb, :view
end

# --- Login Page Template (auth.html.heex) ---
# location: lib/ai_agent_web/templates/auth/login.html.heex
<div class="max-w-md mx-auto text-center mt-20">
  <h1 class="text-2xl font-bold mb-6">Login to Your Agent</h1>
  <a href="/auth/google"
     class="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-500">Sign in with Google</a>
</div>

# --- Router Modifications ---
# Add login page route
scope "/", AiAgentWeb do
  get "/login", AuthController, :login
end

# --- Auth Controller Login Action ---
defmodule AiAgentWeb.AuthController do
  use AiAgentWeb, :controller

  def login(conn, _params) do
    render(conn, "login.html")
  end
end

# --- Google Callback (update to google_oauth.ex) ---
# After fetching user
conn
|> put_session(:user_id, user.id)
|> redirect(to: "/chat")

# --- End-to-End Tool Call Test Setup ---
# Simulate input in iex:
user = AiAgent.Context.Users.get_by_email("test@example.com")
msg = "Schedule an appointment with Sara Smith at 3pm and 4pm"
AiAgent.Context.Chat.ask(user, msg)

# After a second, check Oban queue:
Oban.drain_queue(:default)

# You should see output like:
# {:scheduling_meeting, "Sara Smith", ["3pm", "4pm"]}

# Confirm tool logic executed
# All good: AI parsed intent → matched tool → parameters parsed → job inserted → executed

# Step 7  connect real Gmail + Calendar APIs, add Hubspot data ingestion, or deploy this to Fly.io or Render?

# --- Gmail API: Send Email ---
defmodule AiAgent.Integrations.Gmail do
  def send_email(user, to, subject, body) do
    token = user.google_tokens["access"]
    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    raw = Base.encode64("""
    To: #{to}
    Subject: #{subject}
    Content-Type: text/plain; charset="UTF-8"

    #{body}
    """ |> String.trim())

    Req.post!("https://gmail.googleapis.com/gmail/v1/users/me/messages/send", 
      headers: headers,
      json: %{raw: raw}
    )
  end
end

# --- Google Calendar API: Create Event ---
defmodule AiAgent.Integrations.Calendar do
  def create_event(user, summary, start_time, end_time, attendees \\ []) do
    token = user.google_tokens["access"]
    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    Req.post!("https://www.googleapis.com/calendar/v3/calendars/primary/events",
      headers: headers,
      json: %{
        summary: summary,
        start: %{dateTime: start_time},
        end: %{dateTime: end_time},
        attendees: Enum.map(attendees, &%{email: &1})
      }
    )
  end
end

# --- Hubspot Ingestion ---
defmodule AiAgent.Integrations.Hubspot do
  def fetch_contacts(user) do
    token = user.hubspot_tokens
    headers = [{"Authorization", "Bearer #{token}"}]

    %{"results" => contacts} =
      Req.get!("https://api.hubapi.com/crm/v3/objects/contacts?properties=firstname,lastname,email",
        headers: headers
      ).body

    contacts
  end

  def fetch_notes(user) do
    token = user.hubspot_tokens
    headers = [{"Authorization", "Bearer #{token}"}]

    %{"results" => notes} =
      Req.get!("https://api.hubapi.com/crm/v3/objects/notes",
        headers: headers
      ).body

    notes
  end
end

# --- Fly.io Deployment Steps ---
# In terminal:
# 1. Install Fly CLI: https://fly.io/docs/hands-on/install-flyctl/
# 2. Authenticate:
#    fly auth login
# 3. Create app:
#    fly launch --name ai-agent-finance --region sjc --no-deploy
# 4. Set secrets:
#    fly secrets set GOOGLE_CLIENT_ID=xxx GOOGLE_CLIENT_SECRET=xxx OPENAI_API_KEY=sk-xxx HUBSPOT_CLIENT_ID=xxx HUBSPOT_CLIENT_SECRET=xxx
# 5. Build & Deploy:
#    fly deploy

# --- fly.toml Example ---
[app]
name = "ai-agent-finance"

[build]
builder = "heroku/buildpacks:20"

[env]
MIX_ENV = "prod"
PORT = "8080"

[[services]]
internal_port = 8080
protocol = "tcp"

  [[services.ports]]
  handlers = ["http"]
  port = 80

  [[services.ports]]
  handlers = ["tls", "http"]
  port = 443

  # Step 8, concepts

  # 🧠 AI Agent for Financial Advisors — Architecture & Explanation

This is a breakdown of how the app works and how each part connects. It covers authentication, data handling, LLM usage, tool calling, memory, and deployment.

---

## 🔐 Authentication (Google & Hubspot OAuth)

### Purpose:
Allows a user to securely log in and connect to their Gmail, Calendar, and Hubspot accounts.

### Flow:
1. User clicks “Sign in with Google” → Redirected to Google OAuth page.
2. They authorize permissions → Google returns a temporary `code`.
3. Backend exchanges the `code` for an `access_token` and `refresh_token`.
4. We store these tokens in the database (in the `users` table).
5. We save their `user_id` in session → now they are logged in!

Same logic applies for Hubspot, using its OAuth endpoint.

---

## 🔗 App Intercommunication

- We use Phoenix LiveView for frontend-to-backend reactivity.
- Backend context modules manage business logic (ex: `Chat.ask/2`).
- LiveView `ChatLive` handles chat rendering and event handling.
- Tools are triggered either immediately (on chat) or via webhooks.

---

## 🧠 RAG: Retrieval-Augmented Generation

**RAG = Use stored knowledge (documents/emails/notes) to improve LLM answers**

### Flow:
1. We fetch user’s emails and Hubspot data.
2. We store it in the `documents` table, with vector embeddings (OpenAI's `text-embedding-3-small` model).
3. On each question, we search the most relevant entries (via pgvector).
4. This “context” is included in the prompt sent to the LLM.

This makes the AI much more knowledgeable and specific.

---

## 🧰 LLM + Tool Calling

We use **OpenAI GPT-4o** with tool/function calling enabled.

### Tool Example:
- Tool name: `schedule_meeting`
- Arguments: contact name + list of times

The model will:
- Understand intent from user input (e.g. “Book with Sara at 4pm”)
- Auto-call the tool and pass parsed arguments
- ToolExecutor (via Oban) runs the actual code (e.g. Google Calendar API)

---

## 🗂️ Memory: Long-Term Instructions

Memory is user-specific instructions like:
- “When someone emails me, create a Hubspot contact”
- “When I create a calendar event, send attendees a reminder email”

We store these as rows in a `memories` table. They are:
- Recalled and included in every prompt
- Checked on each event via webhook or polling

---

## 🔁 Event Handling (Webhook & Proactive Agent)

### Example:
1. User receives new email → Gmail webhook triggers `/webhook/gmail`
2. We parse the event + load user memory
3. AI is asked: “Given this new email and these instructions, do anything?”
4. It may reply with a tool call — which is executed via Oban

This enables "proactive" agent behavior.

---

## 🛠️ Deployment

We deploy to **Fly.io** using:
- `fly.toml` config
- Secret injection for API keys
- PostgreSQL with `pgvector` extension for embeddings

Everything runs serverless, with Oban jobs handling background work.

---

## 🧩 Tech Summary

| Layer            | Tech                                  |
|------------------|----------------------------------------|
| Language         | Elixir                                 |
| Framework        | Phoenix + LiveView                     |
| Background Jobs  | Oban                                   |
| LLM              | OpenAI GPT-4o with function calling    |
| Embeddings       | OpenAI `text-embedding-3-small`        |
| Vector DB        | Postgres + pgvector                    |
| OAuth Providers  | Google, Hubspot                        |
| Deployment       | Fly.io                                 |

---

This app makes heavy use of AI to handle data, automate communication, and enable a financial assistant that adapts to users’ workflows and instructions.


# Step 9 Summary of What This AI Agent Does

### 1.1 — For a Non-Technical Audience
This app is like a smart digital assistant for financial advisors. It reads your emails, calendar, and client notes, and helps you:
- Remember things clients said
- Answer questions about your client history
- Automatically reply to emails
- Schedule meetings for you
- Handle repetitive tasks (like sending follow-ups)

It feels like chatting with a helpful assistant that knows your clients and helps you save time.

---

### 1.2 — For a Technical Audience
This is a full-stack Elixir/Phoenix app with:
- Google OAuth (Gmail + Calendar) and Hubspot OAuth integration
- RAG (retrieval-augmented generation) using OpenAI embeddings + pgvector
- GPT-4o with tool calling for dynamic task execution
- Persistent memory via Ecto schemas for long-term instruction adherence
- Webhook & polling-based event handling
- Oban for asynchronous tool execution
- LiveView chat UI and Fly.io deployment

It enables a user-specific, proactive agent that responds to live data changes across services.

---

### 1.3 — For You, as a Developer
Think of this as a modern, integrated event-driven system where:
- The LLM is the "brains"
- RAG is how it "remembers context"
- OAuth connects the "senses" (email, CRM, calendar)
- Tool calling is how it "takes action"
- Memory is how it follows ongoing behavior
- Oban is how you execute and track background jobs

You’re building something where:
- A user can *talk* to it
- The agent *knows things* from external data
- The agent can *do things* using tools
- And it can *remember and react* when new events happen

Your job is to build strong foundations in each layer (auth, retrieval, action, automation) and then link them together with consistent prompt design.

---

## 📋 Suggested Order of Implementation

### 🥇 Step 1: OAuth + Session Management (Easy + Foundation)
- Google login (email, calendar access)
- Hubspot login
- Store tokens in DB
- Set user session

**Why:** Enables all integrations + personalizes the agent.

---

### 🥈 Step 2: Chat UI + OpenAI Tool Call Integration
- LiveView chat
- OpenAI GPT-4o with tool schema
- Stub tools (log or simulate execution)

**Why:** Core agent interface + tool testbed. Useful early!

---

### 🥉 Step 3: RAG Setup (Embeddings + Vector DB)
- Store emails and Hubspot notes into `documents`
- Use OpenAI embeddings
- Search most relevant docs

**Why:** Boosts agent context awareness, crucial for good responses.

---

### 🏗️ Step 4: Memory & Instruction Storage
- Let user give persistent rules ("always do X")
- Include them in prompts

**Why:** Enables automation and reaction to events.

---

### ⚡ Step 5: Event Hooks + Oban Tool Execution
- Gmail / Calendar / Hubspot webhooks
- Trigger AI when things change
- Run jobs via Oban when needed

**Why:** Now the agent becomes proactive!

---

### 🚀 Step 6: Productionization
- Error handling, logging, retries
- Secrets, Fly.io deploy, seed data
- Polishing, UI/UX, onboarding

**Why:** Wrap it up for users, demo, or go live.

---

## ✅ Final Notes
You’ll work best by building in small vertical slices: for example, one complete flow like:
> Log in → Chat → Ask to email client → Tool runs → Done

Then layer in memory, events, and integrations progressively.


# Step 10 - seed
# --- Gmail + Hubspot Mock Seed Data ---
defmodule AiAgent.Seeds do
  alias AiAgent.Repo
  alias AiAgent.Schemas.{User, Document, Memory}

  def seed_all do
    user = Repo.insert!(%User{
      email: "test@example.com",
      google_tokens: %{"access" => "mock-token"},
      hubspot_tokens: "mock-hubspot-token"
    })

    insert_documents(user)
    insert_memory(user)
  end

  defp insert_documents(user) do
    emails = [
      {"client_a@example.com", "My kid plays baseball on Saturdays."},
      {"client_b@example.com", "I'm thinking of selling my AAPL shares."}
    ]

    Enum.each(emails, fn {from, content} ->
      Repo.insert!(%Document{
        user_id: user.id,
        source: from,
        type: "email",
        content: content,
        embedding: :rand.uniform() |> List.duplicate(1536)  # fake vector for now
      })
    end)
  end

  defp insert_memory(user) do
    Repo.insert!(%Memory{
      user_id: user.id,
      instruction: "When someone emails me that's not in Hubspot, create a contact."
    })
  end
end

# --- Unit Tests (chat_test.exs) ---
defmodule AiAgent.ChatTest do
  use ExUnit.Case, async: true
  alias AiAgent.Context.Chat

  test "chat returns basic response" do
    user = %AiAgent.Schemas.User{id: 123, email: "x@example.com"}
    result = Chat.ask(user, "Hello")
    assert is_binary(result)
  end
end

# --- Integration Test (tool_call_test.exs) ---
defmodule AiAgent.ToolCallTest do
  use ExUnit.Case
  alias AiAgent.LLM.Agent

  test "schedules a meeting via tool" do
    user = %AiAgent.Schemas.User{id: 1, google_tokens: %{"access" => "test"}}
    input = "Schedule an appointment with John at 10am and 2pm"

    response = Agent.chat(user, input)
    assert response =~ "Tool call"
  end
end

# --- Prompt Test Cases ---
defmodule AiAgent.PromptBuilderTest do
  use ExUnit.Case
  alias AiAgent.LLM.PromptBuilder

  test "builds correct prompt" do
    msg = "Why did Greg want to sell AAPL?"
    context = "Email: 'I'm thinking of selling my AAPL shares.'"
    memory = ["Always summarize client requests."]

    prompt = PromptBuilder.build(msg, context, memory)
    assert Enum.count(prompt) == 3
    assert Enum.any?(prompt, fn p -> String.contains?(p.content, "AAPL") end)
  end
end


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