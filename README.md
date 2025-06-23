# 🧠 AI Agent for Financial Advisors

A full-stack Elixir/Phoenix app that connects Gmail, Google Calendar, and Hubspot, enabling a proactive AI assistant for financial advisors. It leverages OpenAI GPT-4o, RAG (retrieval-augmented generation), tool calling, persistent memory, and background jobs.

---

## 🚀 Quick Start

1. **Clone & Setup**
  ```sh
  git clone https://github.com/your-org/ai_agent.git
  cd ai_agent
  mix deps.get
  ```

2. **Database & Migrations**
  ```sh
  mix ecto.create
  mix ecto.migrate
  ```

3. **Configure Secrets**
  Set these environment variables:
  - `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REDIRECT_URI`
  - `HUBSPOT_CLIENT_ID`, `HUBSPOT_CLIENT_SECRET`, `HUBSPOT_REDIRECT_URI`
  - `OPENAI_API_KEY`

4. **Run the Server**
  ```sh
  mix phx.server
  ```
  Visit [localhost:4000](http://localhost:4000)

---

## 🏗️ Architecture Overview

| Layer            | Tech                                  |
|------------------|----------------------------------------|
| Language         | Elixir                                 |
| Framework        | Phoenix + LiveView                     |
| Background Jobs  | Oban                                   |
| LLM              | OpenAI GPT-4o with tool calling        |
| Embeddings       | OpenAI `text-embedding-3-small`        |
| Vector DB        | Postgres + pgvector                    |
| OAuth Providers  | Google, Hubspot                        |
| Deployment       | Fly.io                                 |

---

## 🔐 Authentication

- **Google OAuth**: Login, Gmail, Calendar access
- **Hubspot OAuth**: CRM access
- Tokens are stored in the `users` table.

---

## 💬 Chat UI

- Built with Phoenix LiveView.
- Ask questions, trigger tools, and get responses in real time.

---

## 🧠 RAG (Retrieval-Augmented Generation)

- Ingests emails and Hubspot notes.
- Stores as vector embeddings in Postgres (`pgvector`).
- Fetches relevant context for each LLM prompt.

---

## 🛠️ Tool Calling

- Define tools (e.g., `schedule_meeting`, `send_email`) as JSON schemas.
- LLM can call tools with structured arguments.
- Tool execution is handled via Oban background jobs.

---

## 🗂️ Memory

- Store persistent user instructions (e.g., "Always create a Hubspot contact for new emails").
- Included in every prompt and checked on events.

---

## 🔁 Event Handling

- Webhooks for Gmail, Calendar, and Hubspot.
- On new events, agent checks memory and context, then decides if action is needed.

---

## 🧩 Project Structure

