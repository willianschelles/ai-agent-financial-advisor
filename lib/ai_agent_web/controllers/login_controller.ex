defmodule AiAgentWeb.LoginController do
  use AiAgentWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
