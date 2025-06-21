defmodule AiAgentWeb.AuthController do
  use AiAgentWeb, :controller
  plug Ueberauth

  alias AiAgent.Accounts

  def request(conn, _params), do: conn

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case Accounts.upsert_user_from_auth(auth) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> configure_session(renew: true)
        |> redirect(to: "/chat")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Login failed: \#{reason}")
        |> redirect(to: "/login")
    end
  end
end
