defmodule AiAgentWeb.HealthController do
  use AiAgentWeb, :controller
  alias AiAgent.HealthCheck

  def check(conn, _params) do
    # Get comprehensive health check status
    health_data = HealthCheck.check_system()

    # Convert atom status to string for JSON
    status_string = if health_data.status == :ok, do: "ok", else: "error"

    # Prepare response data
    response_data = Map.put(health_data, :status, status_string)

    # Send appropriate status code based on health
    status_code = if health_data.status == :ok, do: 200, else: 500

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status_code, Jason.encode!(response_data))
  end
end
