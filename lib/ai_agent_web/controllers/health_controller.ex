defmodule AiAgentWeb.HealthController do
  use AiAgentWeb, :controller

  def check(conn, _params) do
    # Simple health check endpoint for Render
    # Checking that the application is running
    # You could add database connectivity checks here if needed
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{status: "ok", timestamp: DateTime.utc_now()}))
  end
end
