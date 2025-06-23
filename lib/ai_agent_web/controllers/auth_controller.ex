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
        |> put_flash(:info, "Successfully connected to Google! You can now connect HubSpot on your dashboard.")
        |> redirect(to: redirect_path)

      {:error, reason} ->
        conn
        |> put_flash(:error, "Google login failed: #{reason}")
        |> IO.inspect(label: "Google Auth Error")
        |> redirect(to: "/login")
    end
  end

  defp handle_hubspot_auth(conn, auth) do
    Logger.info("Processing HubSpot OAuth callback")
    IO.inspect(auth.credentials, label: "Raw HubSpot credentials")
    IO.inspect(auth.credentials.token, label: "Raw token field")
    
    # Parse the token if it's a JSON string, otherwise use as-is
    {access_token, token_type, refresh_token, expires_in} = 
      case auth.credentials.token do
        token when is_binary(token) ->
          # Try to parse as JSON first
          case Jason.decode(token) do
            {:ok, %{"access_token" => access_token, "token_type" => token_type, 
                    "refresh_token" => refresh_token, "expires_in" => expires_in}} ->
              {access_token, token_type, refresh_token, expires_in}
            {:error, _} ->
              # Not JSON, use the raw token
              {token, auth.credentials.token_type, auth.credentials.refresh_token, auth.credentials.expires_at}
          end
        token ->
          # Not a string, use as-is
          {token, auth.credentials.token_type, auth.credentials.refresh_token, auth.credentials.expires_at}
      end
    
    # Extract HubSpot tokens from auth
    tokens = %{
      access_token: access_token,
      token_type: token_type,
      refresh_token: refresh_token,
      expires_in: expires_in
    }
    
    IO.inspect(tokens, label: "Parsed tokens")
    
    # Try to find user by ID (from session) first, then fallback to email
    user_result = case get_session(conn, :user_id) do
      nil -> 
        Logger.info("No user_id in session, trying email fallback")
        # Fallback: try to find by email (if HubSpot provides it)
        email = auth.info.email
        if email && email != "user@hubspot.com" do
          case Accounts.upsert_hubspot_tokens(email, tokens) do
            {:ok, user} -> {:ok, user}
            {:error, _} -> {:error, "User not found by email: #{email}"}
          end
        else
          {:error, "No user ID in session and no valid email from HubSpot"}
        end
      
      user_id when is_integer(user_id) or is_binary(user_id) ->
        Logger.info("Found user_id in session: #{user_id}")
        user_id = if is_binary(user_id), do: String.to_integer(user_id), else: user_id
        Accounts.upsert_hubspot_tokens(user_id, tokens)
    end

    case user_result do
      {:ok, user} ->
        redirect_path = determine_redirect_path(user, "hubspot")
        
        conn
        |> put_session(:user_id, user.id)
        |> configure_session(renew: true)
        |> put_flash(:info, "HubSpot connected successfully!")
        |> redirect(to: redirect_path)

      {:error, reason} ->
        Logger.error("HubSpot connection failed: #{reason}")
        conn
        |> put_flash(:error, "HubSpot connection failed: #{reason}")
        |> redirect(to: "/login")
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
        # After Google auth, redirect to dashboard to connect HubSpot
        "/dashboard"
      
      "hubspot" ->
        # HubSpot connection - if they now have both, they're fully set up
        if has_google and has_hubspot do
          # Trigger initial RAG data ingestion now that both services are connected
          Task.start(fn -> 
            AiAgent.Embeddings.RAG.initialize_for_user(user)
          end)
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
