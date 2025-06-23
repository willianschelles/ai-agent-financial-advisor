defmodule AiAgentWeb.DashboardLive do
  use AiAgentWeb, :live_view

  alias AiAgent.Accounts

  def mount(_params, session, socket) do
    user = Accounts.get_user!(session["user_id"])
    
    {:ok, assign(socket, 
      current_user: user,
      google_connected: has_google_tokens?(user),
      hubspot_connected: has_hubspot_tokens?(user),
      setup_complete: setup_complete?(user)
    )}
  end

  def handle_event("connect_hubspot", _params, socket) do
    # This will redirect to the HubSpot OAuth flow
    {:noreply, redirect(socket, to: "/auth/hubspot")}
  end

  def handle_event("disconnect_hubspot", _params, socket) do
    user = socket.assigns.current_user
    
    case Accounts.disconnect_hubspot(user) do
      {:ok, updated_user} ->
        socket = assign(socket, 
          current_user: updated_user,
          hubspot_connected: false,
          setup_complete: setup_complete?(updated_user)
        )
        {:noreply, put_flash(socket, :info, "HubSpot disconnected successfully")}
      
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to disconnect HubSpot: #{reason}")}
    end
  end

  def handle_event("refresh_data", _params, socket) do
    user = socket.assigns.current_user
    
    # Trigger data refresh in background
    Task.start(fn ->
      case AiAgent.Embeddings.RAG.refresh_user_data(user, %{clear_existing: false}) do
        {:ok, result} ->
          send(self(), {:data_refresh_complete, result})
        {:error, reason} ->
          send(self(), {:data_refresh_error, reason})
      end
    end)
    
    socket = put_flash(socket, :info, "Data refresh started in background...")
    {:noreply, socket}
  end

  def handle_event("test_connection", %{"service" => service}, socket) do
    user = socket.assigns.current_user
    
    case test_service_connection(user, service) do
      {:ok, _result} ->
        {:noreply, put_flash(socket, :info, "#{String.capitalize(service)} connection is working!")}
      
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "#{String.capitalize(service)} connection failed: #{reason}")}
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

  defp setup_complete?(user) do
    has_google_tokens?(user) and has_hubspot_tokens?(user)
  end

  defp test_service_connection(user, "google") do
    # Test Google API connection by making a simple request
    case AiAgent.Google.GmailAPI.get_profile(user) do
      {:ok, _profile} -> {:ok, "Google connection verified"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp test_service_connection(user, "hubspot") do
    # Test HubSpot API connection
    case AiAgent.LLM.Tools.HubSpotTool.test_connection(user) do
      {:ok, _result} -> {:ok, "HubSpot connection verified"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp test_service_connection(_user, _service) do
    {:error, "Unknown service"}
  end

  def handle_info({:data_refresh_complete, result}, socket) do
    message = case result do
      %{gmail: gmail_count, hubspot: hubspot_count} ->
        "Data refresh complete! Processed #{gmail_count} Gmail messages and #{hubspot_count} HubSpot records."
      _ ->
        "Data refresh completed successfully."
    end
    
    {:noreply, put_flash(socket, :info, message)}
  end

  def handle_info({:data_refresh_error, reason}, socket) do
    {:noreply, put_flash(socket, :error, "Data refresh failed: #{reason}")}
  end
end