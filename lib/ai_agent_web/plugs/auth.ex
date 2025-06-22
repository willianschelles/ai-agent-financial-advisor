defmodule AiAgentWeb.Plugs.Auth do
  import Plug.Conn
  alias AiAgent.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    IO.inspect(get_session(conn, :user_id), label: "[Auth Plug] User ID in session")

    case get_session(conn, :user_id) do
      nil ->
        conn
        |> Phoenix.Controller.redirect(to: "/login")
        |> halt()

      user_id ->
        assign(conn, :current_user, Accounts.get_user!(user_id))
    end
  end
end
