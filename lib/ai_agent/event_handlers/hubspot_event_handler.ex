defmodule AiAgent.EventHandlers.HubSpotEventHandler do
  @moduledoc """
  Handles HubSpot webhook events and resumes waiting tasks.
  
  This module processes HubSpot notifications for contact updates, deal changes,
  and other CRM events that may trigger task resumption.
  """
  
  require Logger
  
  alias AiAgent.EventHandlers.WebhookHandler
  
  @doc """
  Handle a HubSpot event from webhook.
  
  ## Parameters
  - webhook_data: HubSpot webhook payload
  - user_id: ID of the user whose HubSpot account was updated
  
  ## Returns
  - {:ok, results} with resumed tasks
  - {:error, reason} if processing failed
  """
  def handle_hubspot_event(webhook_data, user_id) do
    Logger.info("Handling HubSpot event for user #{user_id}")
    
    case parse_hubspot_webhook(webhook_data) do
      {:ok, hubspot_event} ->
        process_hubspot_event(hubspot_event, user_id)
      
      {:error, reason} ->
        Logger.error("Failed to parse HubSpot webhook: #{reason}")
        {:error, reason}
    end
  end
  
  @doc """
  Process a HubSpot event and resume any waiting tasks.
  """
  def process_hubspot_event(hubspot_event, user_id) do
    Logger.info("Processing HubSpot event for user #{user_id}: #{hubspot_event.event_type}")
    
    event_data = %{
      object_id: hubspot_event.object_id,
      object_type: hubspot_event.object_type,
      event_type: hubspot_event.event_type,
      property_changes: hubspot_event.property_changes,
      occurred_at: hubspot_event.occurred_at,
      raw_data: hubspot_event
    }
    
    # Resume tasks based on the type of HubSpot event
    case {hubspot_event.object_type, hubspot_event.event_type} do
      {"contact", "contact.creation"} ->
        handle_contact_creation(event_data, user_id)
      
      {"contact", "contact.propertyChange"} ->
        handle_contact_update(event_data, user_id)
      
      {"deal", "deal.creation"} ->
        handle_deal_creation(event_data, user_id)
      
      {"deal", "deal.propertyChange"} ->
        handle_deal_update(event_data, user_id)
      
      _ ->
        Logger.debug("Unhandled HubSpot event: #{hubspot_event.object_type}.#{hubspot_event.event_type}")
        {:ok, []}
    end
  end
  
  @doc """
  Set up HubSpot webhooks for a user.
  """
  def setup_hubspot_webhooks(user) do
    Logger.info("Setting up HubSpot webhooks for user #{user.id}")
    
    case mock_setup_hubspot_webhooks(user) do
      {:ok, webhook_response} ->
        Logger.info("Successfully set up HubSpot webhooks for user #{user.id}")
        {:ok, webhook_response}
      
      {:error, reason} ->
        Logger.error("Failed to set up HubSpot webhooks for user #{user.id}: #{reason}")
        {:error, reason}
    end
  end
  
  @doc """
  Remove HubSpot webhooks for a user.
  """
  def remove_hubspot_webhooks(user) do
    Logger.info("Removing HubSpot webhooks for user #{user.id}")
    
    case mock_remove_hubspot_webhooks(user) do
      {:ok, _} ->
        Logger.info("Successfully removed HubSpot webhooks for user #{user.id}")
        {:ok, %{status: "removed"}}
      
      {:error, reason} ->
        Logger.error("Failed to remove HubSpot webhooks for user #{user.id}: #{reason}")
        {:error, reason}
    end
  end
  
  # Private helper functions
  
  defp parse_hubspot_webhook(webhook_data) do
    # Parse HubSpot webhook payload
    case webhook_data do
      %{"subscriptionType" => subscription_type, "eventId" => event_id} ->
        hubspot_event = %{
          subscription_type: subscription_type,
          event_id: event_id,
          object_id: Map.get(webhook_data, "objectId"),
          object_type: extract_object_type(subscription_type),
          event_type: subscription_type,
          property_changes: extract_property_changes(webhook_data),
          occurred_at: Map.get(webhook_data, "occurredAt"),
          portal_id: Map.get(webhook_data, "portalId")
        }
        
        {:ok, hubspot_event}
      
      _ ->
        Logger.error("Invalid HubSpot webhook format: #{inspect(webhook_data)}")
        {:error, "Invalid webhook format"}
    end
  end
  
  defp extract_object_type(subscription_type) do
    # Extract object type from subscription type
    case subscription_type do
      "contact." <> _ -> "contact"
      "deal." <> _ -> "deal"
      "company." <> _ -> "company"
      "ticket." <> _ -> "ticket"
      _ -> "unknown"
    end
  end
  
  defp extract_property_changes(webhook_data) do
    # Extract property changes from webhook data
    case Map.get(webhook_data, "propertyChanges") do
      nil -> []
      changes when is_list(changes) ->
        Enum.map(changes, fn change ->
          %{
            property_name: Map.get(change, "propertyName"),
            new_value: Map.get(change, "newValue"),
            previous_value: Map.get(change, "previousValue")
          }
        end)
      _ -> []
    end
  end
  
  defp handle_contact_creation(event_data, user_id) do
    Logger.info("Handling contact creation for user #{user_id}")
    
    # Look for tasks waiting for contact creation
    WebhookHandler.resume_waiting_tasks("webhook_event", event_data, user_id, %{
      object_type: "contact",
      event_type: "creation"
    })
  end
  
  defp handle_contact_update(event_data, user_id) do
    Logger.info("Handling contact update for user #{user_id}")
    
    # Look for tasks waiting for contact updates
    WebhookHandler.resume_waiting_tasks("webhook_event", event_data, user_id, %{
      object_type: "contact",
      event_type: "update",
      object_id: event_data.object_id
    })
  end
  
  defp handle_deal_creation(event_data, user_id) do
    Logger.info("Handling deal creation for user #{user_id}")
    
    # Look for tasks waiting for deal creation
    WebhookHandler.resume_waiting_tasks("webhook_event", event_data, user_id, %{
      object_type: "deal",
      event_type: "creation"
    })
  end
  
  defp handle_deal_update(event_data, user_id) do
    Logger.info("Handling deal update for user #{user_id}")
    
    # Look for tasks waiting for deal updates
    WebhookHandler.resume_waiting_tasks("webhook_event", event_data, user_id, %{
      object_type: "deal",
      event_type: "update",
      object_id: event_data.object_id
    })
  end
  
  # Mock functions for HubSpot API integration
  
  defp mock_setup_hubspot_webhooks(user) do
    Logger.debug("Mock: Setting up HubSpot webhooks for user #{user.id}")
    
    {:ok, %{
      webhook_id: "hubspot-webhook-#{user.id}",
      subscription_types: [
        "contact.creation",
        "contact.propertyChange",
        "deal.creation",
        "deal.propertyChange"
      ],
      target_url: get_hubspot_webhook_url(),
      created_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }}
  end
  
  defp mock_remove_hubspot_webhooks(user) do
    Logger.debug("Mock: Removing HubSpot webhooks for user #{user.id}")
    
    {:ok, %{status: "removed"}}
  end
  
  defp get_hubspot_webhook_url do
    webhook_base = System.get_env("WEBHOOK_BASE_URL") || "https://your-app.com"
    "#{webhook_base}/webhooks/hubspot"
  end
end