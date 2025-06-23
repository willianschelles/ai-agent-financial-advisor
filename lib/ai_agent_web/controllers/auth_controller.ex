defmodule AiAgentWeb.AuthController do
  use AiAgentWeb, :controller
  plug(Ueberauth)

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
        redirect_path = determine_redirect_path(user, "google")
        
        conn
        |> put_session(:user_id, user.id)
        |> put_session(:created_at, DateTime.utc_now() |> DateTime.to_unix())
        |> configure_session(renew: true)
        |> put_flash(:info, "Successfully connected to Google")
        |> redirect(to: redirect_path)

      {:error, reason} ->
        conn
        |> put_flash(:error, "Google login failed: #{reason}")
        |> IO.inspect(label: "Google Auth Error")
        |> redirect(to: "/login")
    end
  end

  defp handle_hubspot_auth(conn, auth) do
    Logger.info("Processing HubSpot auth for user: #{inspect(conn.assigns[:current_user])}")

    case Accounts.connect_hubspot(conn.assigns[:current_user], auth) do
      {:ok, user} ->
        redirect_path = determine_redirect_path(user, "hubspot")
        
        conn
        |> put_session(:user_id, user.id)
        |> configure_session(renew: true)
        |> put_flash(:info, "Successfully connected HubSpot")
        |> redirect(to: redirect_path)

      {:error, reason} ->
        conn
        |> put_flash(:error, "HubSpot connection failed: #{reason}")
        |> redirect(to: "/dashboard")
    end
  end

  def logout(conn, _params) do
    user_id = if conn.assigns[:current_user], do: conn.assigns[:current_user].id, else: "unknown"
    Logger.info("User #{user_id} logging out")
    
    conn
    |> configure_session(drop: true)
    |> clear_session()
    |> put_flash(:info, "You have been logged out successfully")
    |> redirect(to: "/login")
  end

  defp determine_redirect_path(user, auth_type) do
    has_google = has_google_tokens?(user)
    has_hubspot = has_hubspot_tokens?(user)
    
    case auth_type do
      "google" ->
        # First-time Google auth - send to dashboard for onboarding
        if has_google and not has_hubspot do
          "/dashboard"
        else
          # If they already have both, send to chat
          "/chat"
        end
      
      "hubspot" ->
        # HubSpot connection - if they now have both, they're fully set up
        if has_google and has_hubspot do
          "/chat"
        else
          "/dashboard"
        end
      
      _ ->
        "/dashboard"
    end
  end

  defp has_google_tokens?(user) do
    not is_nil(user.google_tokens) and 
    Map.has_key?(user.google_tokens, "access_token") and
    not is_nil(user.google_tokens["access_token"])
  end

  defp has_hubspot_tokens?(user) do
    not is_nil(user.hubspot_tokens) and 
    Map.has_key?(user.hubspot_tokens, "access_token") and
    not is_nil(user.hubspot_tokens["access_token"])
  end

  defp error_message(failure) do
    failure.errors
    |> Enum.map(& &1.message)
    |> Enum.join(", ")
  end
end
