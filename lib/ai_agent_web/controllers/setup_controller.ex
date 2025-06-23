defmodule AiAgentWeb.SetupController do
  use AiAgentWeb, :controller

  def hubspot(conn, _params) do
    render(conn, "hubspot.html")
  end
end