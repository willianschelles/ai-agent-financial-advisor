defmodule AiAgentWeb.AuthController do
  use AiAgentWeb, :controller
  plug Ueberauth

  alias AiAgent.Accounts
  require Logger

  def request(conn, _params) do
    render(conn, "request.html")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    Logger.info("[AuthController] Received auth: #{inspect(auth)}")

    case auth.provider do
      :google ->
        handle_google_auth(conn, auth)

      :hubspot ->
        handle_hubspot_auth(conn, auth)
    end
  end

  def callback(%{assigns: %{ueberauth_failure: failure}} = conn, _params) do
    Logger.error("Authentication failed: #{inspect(failure)}")

    conn
    |> put_flash(:error, "Authentication failed: #{error_message(failure)}")
    |> redirect(to: "/login")
  end

  defp handle_google_auth(conn, auth) do
    case Accounts.upsert_user_from_auth(auth) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> configure_session(renew: true)
        |> redirect(to: "/chat")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Google login failed: #{reason}")
        |> redirect(to: "/login")
    end
  end

  defp handle_hubspot_auth(conn, auth) do
    Logger.info("Processing HubSpot auth for user: #{inspect(conn.assigns[:current_user])}")

    case Accounts.connect_hubspot(conn.assigns[:current_user], auth) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> configure_session(renew: true)
        |> put_flash(:info, "Successfully connected HubSpot")
        |> redirect(to: "/chat")

      {:error, reason} ->
        conn
        |> put_flash(:error, "HubSpot connection failed: #{reason}")
        |> redirect(to: "/chat")
    end
  end

  defp error_message(failure) do
    failure.errors
    |> Enum.map(& &1.message)
    |> Enum.join(", ")
  end
end
