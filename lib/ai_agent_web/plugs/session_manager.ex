defmodule AiAgentWeb.Plugs.SessionManager do
  @moduledoc """
  Session management plug that handles token validation and refresh.
  """
  
  import Plug.Conn
  import Phoenix.Controller
  
  alias AiAgent.Accounts
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :user_id) do
      nil ->
        conn
        
      user_id ->
        user = Accounts.get_user!(user_id)
        
        # Check session age
        case check_session_age(conn) do
          :valid ->
            validate_and_refresh_tokens(conn, user)
            
          :expired ->
            Logger.info("Session expired for user #{user_id}")
            conn
            |> clear_session()
            |> put_flash(:info, "Your session has expired. Please sign in again.")
            |> redirect(to: "/login")
            |> halt()
        end
    end
  end

  defp check_session_age(conn) do
    session_created = get_session(conn, :created_at)
    
    case session_created do
      nil ->
        # Old session without timestamp, consider expired
        :expired
        
      timestamp ->
        created_time = DateTime.from_unix!(timestamp)
        now = DateTime.utc_now()
        age_hours = DateTime.diff(now, created_time, :hour)
        
        # Sessions expire after 24 hours
        if age_hours > 24 do
          :expired
        else
          :valid
        end
    end
  end

  defp validate_and_refresh_tokens(conn, user) do
    # Check Google tokens
    google_valid = validate_google_tokens(user)
    
    # Check HubSpot tokens  
    hubspot_valid = validate_hubspot_tokens(user)
    
    cond do
      not google_valid ->
        Logger.warning("Google tokens invalid for user #{user.id}")
        conn
        |> clear_session()
        |> put_flash(:error, "Your Google authentication has expired. Please sign in again.")
        |> redirect(to: "/login")
        |> halt()
        
      not hubspot_valid and not is_nil(user.hubspot_tokens) ->
        Logger.warning("HubSpot tokens invalid for user #{user.id}")
        # Don't force logout for HubSpot, just disconnect it
        {:ok, updated_user} = Accounts.disconnect_hubspot(user)
        conn
        |> assign(:current_user, updated_user)
        |> put_flash(:warning, "Your HubSpot connection has expired. Please reconnect in your dashboard.")
        
      true ->
        assign(conn, :current_user, user)
    end
  end

  defp validate_google_tokens(user) do
    case user.google_tokens do
      nil ->
        false
        
      tokens ->
        access_token = Map.get(tokens, "access_token")
        refresh_token = Map.get(tokens, "refresh_token")
        
        cond do
          is_nil(access_token) ->
            false
            
          is_nil(refresh_token) ->
            # Without refresh token, we can't renew access
            test_google_token(access_token)
            
          true ->
            # Try to use current token, refresh if needed
            if test_google_token(access_token) do
              true
            else
              refresh_google_tokens(user, refresh_token)
            end
        end
    end
  end

  defp validate_hubspot_tokens(user) do
    case user.hubspot_tokens do
      nil ->
        true  # No HubSpot tokens is OK
        
      tokens ->
        access_token = Map.get(tokens, "access_token")
        
        if is_nil(access_token) do
          false
        else
          test_hubspot_token(access_token)
        end
    end
  end

  defp test_google_token(access_token) do
    # Test the token by making a simple API call
    case AiAgent.Google.GmailAPI.test_token(access_token) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp test_hubspot_token(access_token) do
    # Test HubSpot token
    case AiAgent.LLM.Tools.HubSpotTool.test_token(access_token) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp refresh_google_tokens(user, refresh_token) do
    case AiAgent.Google.OAuth.refresh_token(refresh_token) do
      {:ok, new_tokens} ->
        # Update user with new tokens
        updated_tokens = Map.merge(user.google_tokens, new_tokens)
        
        case Accounts.update_google_tokens(user, updated_tokens) do
          {:ok, _updated_user} ->
            Logger.info("Successfully refreshed Google tokens for user #{user.id}")
            true
            
          {:error, reason} ->
            Logger.error("Failed to save refreshed Google tokens for user #{user.id}: #{reason}")
            false
        end
        
      {:error, reason} ->
        Logger.error("Failed to refresh Google tokens for user #{user.id}: #{reason}")
        false
    end
  end
end