defmodule AiAgent.Embeddings.Troubleshoot do
  @moduledoc """
  Troubleshooting functions for debugging the embeddings and data ingestion issues.
  """

  alias AiAgent.Embeddings.HubSpotDebug
  alias AiAgent.Embeddings.DataIngestion
  alias AiAgent.User
  alias AiAgent.Repo

  @doc """
  Quick troubleshoot function for HubSpot issues.

  ## Usage in IEx:
  # First, get your user
  iex> user = AiAgent.Repo.get_by(AiAgent.User, email: "your-email@example.com")
  iex> AiAgent.Embeddings.Troubleshoot.diagnose_hubspot_issue(user)
  """
  def diagnose_hubspot_issue(%User{} = user) do
    IO.puts("🔍 === HUBSPOT ISSUE DIAGNOSIS ===")
    IO.puts("User: #{user.email}")

    # Step 1: Check basic token presence and format
    IO.puts("\n1️⃣ Checking token presence and format...")

    case user.hubspot_tokens do
      nil ->
        IO.puts("❌ ISSUE FOUND: No HubSpot tokens stored for this user")
        IO.puts("💡 SOLUTION: User needs to authenticate with HubSpot first")
        IO.puts("   Run the OAuth flow: /auth/hubspot")
        return_solution("no_tokens")

      tokens ->
        IO.puts("✅ HubSpot tokens are present")

        # Step 2: Check token format and extract access token
        IO.puts("\n2️⃣ Checking token format...")

        access_token =
          case tokens do
            token when is_binary(token) ->
              IO.puts("✅ Token format: String")
              token

            %{"access_token" => token} when is_binary(token) ->
              IO.puts("✅ Token format: Map with 'access_token' key")
              token

            %{access_token: token} when is_binary(token) ->
              IO.puts("✅ Token format: Map with :access_token key")
              token

            map when is_map(map) ->
              IO.puts("❌ ISSUE FOUND: Map format but no access_token found")
              IO.puts("Available keys: #{inspect(Map.keys(map))}")
              IO.inspect(map, label: "Full token map", pretty: true)
              return_solution("invalid_token_map")

            other ->
              IO.puts("❌ ISSUE FOUND: Unexpected token format")
              IO.inspect(other, label: "Token value", pretty: true)
              return_solution("invalid_token_format")
          end

        if access_token do
          # Step 3: Validate token format
          IO.puts("\n3️⃣ Validating access token...")
          IO.puts("Token length: #{String.length(access_token)} characters")
          IO.puts("Token preview: #{String.slice(access_token, 0, 20)}...")

          if String.length(access_token) < 20 do
            IO.puts("⚠️  WARNING: Token seems unusually short")
          end

          # Step 4: Test the token with HubSpot API
          IO.puts("\n4️⃣ Testing token with HubSpot API...")

          case test_hubspot_token(access_token) do
            {:ok, _} ->
              IO.puts("✅ Token is working! The issue might be elsewhere.")
              suggest_other_solutions()

            {:error, :auth_failed} ->
              return_solution("token_invalid")

            {:error, :forbidden} ->
              return_solution("insufficient_permissions")

            {:error, reason} ->
              IO.puts("❌ API test failed: #{reason}")
              return_solution("api_error")
          end
        end
    end
  end

  @doc """
  Test a HubSpot access token directly.
  """
  def test_hubspot_token(access_token) when is_binary(access_token) do
    headers = [{"Authorization", "Bearer #{access_token}"}]
    url = "https://api.hubapi.com/crm/v3/objects/contacts"
    params = %{limit: 1}

    case Req.get(url, headers: headers, params: params) do
      {:ok, %{status: 200}} ->
        {:ok, "Token valid"}

      {:ok, %{status: 401}} ->
        {:error, :auth_failed}

      {:ok, %{status: 403}} ->
        {:error, :forbidden}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, "Network: #{inspect(reason)}"}
    end
  end

  # Private helper functions

  defp return_solution("no_tokens") do
    IO.puts("\n🚀 === SOLUTION ===")
    IO.puts("The user hasn't authenticated with HubSpot yet.")
    IO.puts("")
    IO.puts("Steps to fix:")
    IO.puts("1. Make sure your HubSpot OAuth app is set up correctly")
    IO.puts("2. Visit /auth/hubspot in your browser")
    IO.puts("3. Complete the OAuth flow")
    IO.puts("4. Try the ingestion again")
    IO.puts("")
    IO.puts("Environment variables needed:")
    IO.puts("- HUBSPOT_CLIENT_ID")
    IO.puts("- HUBSPOT_CLIENT_SECRET")
    IO.puts("- HUBSPOT_REDIRECT_URI (optional, defaults to localhost:4000)")

    check_environment_variables()
  end

  defp return_solution("token_invalid") do
    IO.puts("\n🚀 === SOLUTION ===")
    IO.puts("The HubSpot access token is invalid or expired.")
    IO.puts("")
    IO.puts("Steps to fix:")
    IO.puts("1. Re-authenticate with HubSpot: /auth/hubspot")
    IO.puts("2. Check if your HubSpot app is still active")
    IO.puts("3. Verify the token hasn't been revoked")
    IO.puts("")
    IO.puts("If problem persists:")
    IO.puts("- Check HubSpot developer console for your app")
    IO.puts("- Verify OAuth scopes are correct")
    IO.puts("- Check if account has required permissions")
  end

  defp return_solution("insufficient_permissions") do
    IO.puts("\n🚀 === SOLUTION ===")
    IO.puts("The token is valid but lacks required permissions.")
    IO.puts("")
    IO.puts("Steps to fix:")
    IO.puts("1. Check your HubSpot app scopes include:")
    IO.puts("   - crm.objects.contacts.read")
    IO.puts("   - crm.objects.contacts.write")
    IO.puts("   - crm.objects.notes.read")
    IO.puts("2. Re-authenticate to get updated scopes")
    IO.puts("3. Contact HubSpot admin if you don't have permissions")
  end

  defp return_solution("invalid_token_map") do
    IO.puts("\n🚀 === SOLUTION ===")
    IO.puts("The stored token map doesn't contain the expected 'access_token' field.")
    IO.puts("")
    IO.puts("This usually means:")
    IO.puts("1. The OAuth callback didn't store the token correctly")
    IO.puts("2. The token structure changed")
    IO.puts("")
    IO.puts("Steps to fix:")
    IO.puts("1. Re-authenticate with HubSpot: /auth/hubspot")
    IO.puts("2. Check the OAuth callback code is storing tokens correctly")
  end

  defp return_solution(other) do
    IO.puts("\n❓ === UNKNOWN ISSUE ===")
    IO.puts("Issue type: #{other}")
    IO.puts("Please check the error messages above and:")
    IO.puts("1. Re-authenticate with HubSpot")
    IO.puts("2. Check server logs for more details")
    IO.puts("3. Verify environment variables")
  end

  defp suggest_other_solutions do
    IO.puts("\n🤔 Token seems valid, but ingestion failed. Other possible issues:")
    IO.puts("1. Network connectivity")
    IO.puts("2. Rate limiting")
    IO.puts("3. Empty HubSpot account (no contacts)")
    IO.puts("4. API endpoint changes")
    IO.puts("")
    IO.puts("Try running: AiAgent.Embeddings.HubSpotDebug.full_debug_report(user)")
  end

  defp check_environment_variables do
    IO.puts("\n--- Environment Variables Check ---")

    required_vars = [
      "HUBSPOT_CLIENT_ID",
      "HUBSPOT_CLIENT_SECRET"
    ]

    optional_vars = [
      "HUBSPOT_REDIRECT_URI"
    ]

    all_set =
      Enum.all?(required_vars, fn var ->
        case System.get_env(var) do
          nil ->
            IO.puts("❌ #{var}: NOT SET")
            false

          _value ->
            IO.puts("✅ #{var}: Set")
            true
        end
      end)

    Enum.each(optional_vars, fn var ->
      case System.get_env(var) do
        nil -> IO.puts("⚪ #{var}: Not set (using default)")
        _value -> IO.puts("✅ #{var}: Set")
      end
    end)

    if not all_set do
      IO.puts("\n❌ Missing required environment variables!")
      IO.puts("Set them in your environment or .env file")
    end
  end

  @doc """
  Quick fix attempt - tries to re-authenticate and test again.
  """
  def quick_fix_attempt(user_email) when is_binary(user_email) do
    case Repo.get_by(User, email: user_email) do
      nil ->
        IO.puts("❌ User not found: #{user_email}")
        {:error, "User not found"}

      user ->
        IO.puts("🔧 Starting quick fix for #{user.email}...")

        # Show current status
        diagnose_hubspot_issue(user)

        IO.puts("\n--- Quick Fix Steps ---")
        IO.puts("1. Visit: http://localhost:4000/auth/hubspot")
        IO.puts("2. Complete OAuth flow")
        IO.puts("3. Run: AiAgent.Embeddings.DataIngestion.ingest_hubspot_data(user)")
        IO.puts("")
        IO.puts("Or run this command again to check progress")
    end
  end
end
