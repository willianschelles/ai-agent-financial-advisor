defmodule AiAgent.Google.OAuth do
  @moduledoc """
  Google OAuth token management and refresh functionality.
  """
  
  require Logger

  @token_url "https://oauth2.googleapis.com/token"

  def refresh_token(refresh_token) do
    client_id = System.get_env("GOOGLE_CLIENT_ID")
    client_secret = System.get_env("GOOGLE_CLIENT_SECRET")
    
    if is_nil(client_id) or is_nil(client_secret) do
      {:error, "Google OAuth credentials not configured"}
    else
      body = %{
        grant_type: "refresh_token",
        refresh_token: refresh_token,
        client_id: client_id,
        client_secret: client_secret
      }
      
      headers = [
        {"Content-Type", "application/x-www-form-urlencoded"},
        {"Accept", "application/json"}
      ]
      
      case Req.post(@token_url, form: body, headers: headers) do
        {:ok, %{status: 200, body: response_body}} ->
          parse_token_response(response_body)
          
        {:ok, %{status: status, body: body}} ->
          Logger.error("Google token refresh failed: #{status} - #{inspect(body)}")
          {:error, "Token refresh failed: #{status}"}
          
        {:error, reason} ->
          Logger.error("Google token refresh request failed: #{inspect(reason)}")
          {:error, "Network error during token refresh"}
      end
    end
  end

  defp parse_token_response(response_body) do
    case response_body do
      %{"access_token" => access_token} = tokens ->
        new_tokens = %{
          "access_token" => access_token,
          "token_type" => Map.get(tokens, "token_type", "Bearer"),
          "expires_in" => Map.get(tokens, "expires_in"),
          "scope" => Map.get(tokens, "scope")
        }
        
        # Only include refresh_token if provided (Google doesn't always return it)
        new_tokens = case Map.get(tokens, "refresh_token") do
          nil -> new_tokens
          refresh_token -> Map.put(new_tokens, "refresh_token", refresh_token)
        end
        
        {:ok, new_tokens}
        
      _ ->
        Logger.error("Invalid token response format: #{inspect(response_body)}")
        {:error, "Invalid token response"}
    end
  end
end