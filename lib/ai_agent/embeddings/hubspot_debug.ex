defmodule AiAgent.Embeddings.HubSpotDebug do
  @moduledoc """
  Debug utilities for HubSpot authentication and API issues.
  """

  require Logger
  alias AiAgent.User

  @doc """
  Debug a user's HubSpot tokens and test authentication.

  ## Usage in IEx:
  iex> AiAgent.Embeddings.HubSpotDebug.debug_user_tokens(user)
  """
  def debug_user_tokens(%User{} = user) do
    IO.puts("=== HubSpot Token Debug ===")
    IO.puts("User ID: #{user.id}")
    IO.puts("Email: #{user.email}")

    case user.hubspot_tokens do
      nil ->
        IO.puts("❌ No HubSpot tokens found")
        {:error, "No HubSpot tokens"}

      tokens when is_binary(tokens) ->
        IO.puts("🔑 HubSpot tokens (string format): #{String.slice(tokens, 0, 20)}...")
        test_token_validity(tokens)

      tokens when is_map(tokens) ->
        IO.puts("🔑 HubSpot tokens (map format):")
        IO.inspect(Map.keys(tokens), label: "Available keys")

        access_token = tokens["access_token"] || tokens[:access_token]

        case access_token do
          nil ->
            IO.puts("❌ No access_token found in map")
            IO.inspect(tokens, label: "Full token map")
            {:error, "No access token in map"}

          token ->
            IO.puts("✓ Access token found: #{String.slice(token, 0, 20)}...")

            # Check if there's an expiry
            expires_at = tokens["expires_at"] || tokens[:expires_at]

            if expires_at do
              IO.puts("⏰ Token expires at: #{expires_at}")

              # Check if expired (if timestamp)
              if is_integer(expires_at) do
                current_time = System.system_time(:second)

                if expires_at < current_time do
                  IO.puts("❌ Token appears to be expired!")
                else
                  IO.puts("✓ Token appears to be valid (not expired)")
                end
              end
            end

            test_token_validity(token)
        end

      other ->
        IO.puts("❓ Unexpected token format:")
        IO.inspect(other)
        {:error, "Unexpected token format"}
    end
  end

  @doc """
  Test if a HubSpot token is valid by making a simple API call.
  """
  def test_token_validity(token) when is_binary(token) do
    IO.puts("\n--- Testing Token Validity ---")

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    # Use a simple endpoint to test authentication
    url = "https://api.hubapi.com/crm/v3/objects/contacts"
    # Just get 1 contact to test auth
    params = %{limit: 1}

    case Req.get(url, headers: headers, params: params) do
      {:ok, %{status: 200, body: body}} ->
        IO.puts("✅ Token is valid! API call successful")

        contacts_count = length(Map.get(body, "results", []))
        IO.puts("📊 Found #{contacts_count} contacts in response")
        {:ok, "Token valid"}

      {:ok, %{status: 401, body: body}} ->
        IO.puts("❌ Token is invalid (401 Unauthorized)")
        IO.puts("Error details:")
        IO.inspect(body, pretty: true)

        # Check specific error messages
        case body do
          %{"message" => message} ->
            IO.puts("📝 Error message: #{message}")

          _ ->
            IO.puts("📝 No specific error message")
        end

        {:error, "Token invalid - 401"}

      {:ok, %{status: status, body: body}} ->
        IO.puts("❓ Unexpected status: #{status}")
        IO.inspect(body, label: "Response body")
        {:error, "Unexpected status: #{status}"}

      {:error, reason} ->
        IO.puts("🌐 Network error:")
        IO.inspect(reason, pretty: true)
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  @doc """
  Check HubSpot token scopes and permissions.
  """
  def check_token_info(token) when is_binary(token) do
    IO.puts("\n--- Checking Token Info ---")

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    # Get token info
    url = "https://api.hubapi.com/oauth/v1/access-tokens/#{token}"

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        IO.puts("✅ Token info retrieved:")
        IO.inspect(body, pretty: true)

        scopes = Map.get(body, "scopes", [])
        IO.puts("🔐 Available scopes: #{Enum.join(scopes, ", ")}")

        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        IO.puts("❌ Failed to get token info: #{status}")
        IO.inspect(body, pretty: true)
        {:error, "Token info request failed: #{status}"}

      {:error, reason} ->
        IO.puts("🌐 Network error getting token info:")
        IO.inspect(reason, pretty: true)
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  @doc """
  Generate a new HubSpot OAuth URL for re-authentication.
  """
  def generate_reauth_url do
    client_id = System.get_env("HUBSPOT_CLIENT_ID")

    redirect_uri =
      System.get_env("HUBSPOT_REDIRECT_URI") || "http://localhost:4000/auth/hubspot/callback"

    if client_id do
      scopes = "oauth crm.objects.contacts.read crm.objects.contacts.write crm.objects.notes.read"

      url =
        "https://app.hubspot.com/oauth/authorize?" <>
          URI.encode_query(%{
            client_id: client_id,
            redirect_uri: redirect_uri,
            scope: scopes,
            response_type: "code"
          })

      IO.puts("🔗 Re-authentication URL:")
      IO.puts(url)
      IO.puts("\nCopy this URL to your browser to re-authenticate with HubSpot")

      {:ok, url}
    else
      IO.puts("❌ HUBSPOT_CLIENT_ID environment variable not set")
      {:error, "Missing client ID"}
    end
  end

  @doc """
  Complete debugging report for a user.
  """
  def full_debug_report(%User{} = user) do
    IO.puts("🔍 === COMPLETE HUBSPOT DEBUG REPORT ===")
    IO.puts("Timestamp: #{DateTime.utc_now()}")
    IO.puts("User: #{user.email} (ID: #{user.id})")

    # 1. Check tokens
    case debug_user_tokens(user) do
      {:ok, _} ->
        IO.puts("\n✅ Token validation passed")

        # If we have a valid token, check additional info
        if user.hubspot_tokens do
          token =
            case user.hubspot_tokens do
              token when is_binary(token) -> token
              %{"access_token" => token} -> token
              %{access_token: token} -> token
              _ -> nil
            end

          if token do
            check_token_info(token)
          end
        end

      {:error, reason} ->
        IO.puts("\n❌ Token validation failed: #{reason}")
        IO.puts("\nRecommended actions:")
        IO.puts("1. Re-authenticate with HubSpot")
        IO.puts("2. Check if your HubSpot app has correct scopes")
        IO.puts("3. Verify your environment variables")

        generate_reauth_url()
    end

    # 2. Check environment variables
    IO.puts("\n--- Environment Variables ---")
    env_vars = ["HUBSPOT_CLIENT_ID", "HUBSPOT_CLIENT_SECRET", "HUBSPOT_REDIRECT_URI"]

    Enum.each(env_vars, fn var ->
      case System.get_env(var) do
        nil -> IO.puts("❌ #{var}: Not set")
        value -> IO.puts("✅ #{var}: #{String.slice(value, 0, 10)}...")
      end
    end)

    IO.puts("\n=== END DEBUG REPORT ===")
  end
end
