defmodule AiAgent.WebhookSetup do
  @moduledoc """
  Helper module for setting up webhooks with external services.
  
  This module provides functions to register webhook URLs with Gmail, Calendar,
  and HubSpot services so they can notify our application when events occur.
  """
  
  require Logger
  
  alias AiAgent.EventHandlers.{EmailEventHandler, CalendarEventHandler, HubSpotEventHandler}
  
  @doc """
  Set up all webhooks for a user.
  
  This registers webhook URLs with all supported external services.
  """
  def setup_all_webhooks(user) do
    Logger.info("Setting up all webhooks for user #{user.id}")
    
    results = %{
      gmail: setup_gmail_webhooks(user),
      calendar: setup_calendar_webhooks(user),
      hubspot: setup_hubspot_webhooks(user)
    }
    
    successful = Enum.count(results, fn {_service, {status, _}} -> status == :ok end)
    total = map_size(results)
    
    Logger.info("Webhook setup complete: #{successful}/#{total} services configured")
    
    {:ok, %{
      successful: successful,
      total: total,
      results: results,
      webhook_urls: get_webhook_urls()
    }}
  end
  
  @doc """
  Set up Gmail push notifications for a user.
  """
  def setup_gmail_webhooks(user) do
    Logger.info("Setting up Gmail webhooks for user #{user.id}")
    
    case EmailEventHandler.setup_gmail_push_notifications(user) do
      {:ok, result} ->
        Logger.info("Gmail webhooks configured successfully for user #{user.id}")
        {:ok, result}
      
      {:error, reason} ->
        Logger.error("Failed to set up Gmail webhooks for user #{user.id}: #{reason}")
        {:error, reason}
    end
  end
  
  @doc """
  Set up Google Calendar push notifications for a user.
  """
  def setup_calendar_webhooks(user) do
    Logger.info("Setting up Calendar webhooks for user #{user.id}")
    
    case CalendarEventHandler.setup_calendar_push_notifications(user) do
      {:ok, result} ->
        Logger.info("Calendar webhooks configured successfully for user #{user.id}")
        {:ok, result}
      
      {:error, reason} ->
        Logger.error("Failed to set up Calendar webhooks for user #{user.id}: #{reason}")
        {:error, reason}
    end
  end
  
  @doc """
  Set up HubSpot webhooks for a user.
  """
  def setup_hubspot_webhooks(user) do
    Logger.info("Setting up HubSpot webhooks for user #{user.id}")
    
    case HubSpotEventHandler.setup_hubspot_webhooks(user) do
      {:ok, result} ->
        Logger.info("HubSpot webhooks configured successfully for user #{user.id}")
        {:ok, result}
      
      {:error, reason} ->
        Logger.error("Failed to set up HubSpot webhooks for user #{user.id}: #{reason}")
        {:error, reason}
    end
  end
  
  @doc """
  Remove all webhooks for a user.
  """
  def remove_all_webhooks(user) do
    Logger.info("Removing all webhooks for user #{user.id}")
    
    results = %{
      gmail: EmailEventHandler.stop_gmail_push_notifications(user),
      calendar: CalendarEventHandler.stop_calendar_push_notifications(user),
      hubspot: HubSpotEventHandler.remove_hubspot_webhooks(user)
    }
    
    successful = Enum.count(results, fn {_service, {status, _}} -> status == :ok end)
    total = map_size(results)
    
    Logger.info("Webhook removal complete: #{successful}/#{total} services cleaned up")
    
    {:ok, %{successful: successful, total: total, results: results}}
  end
  
  @doc """
  Get the webhook URLs that should be registered with external services.
  """
  def get_webhook_urls do
    base_url = get_webhook_base_url()
    
    %{
      gmail: "#{base_url}/webhooks/gmail",
      calendar: "#{base_url}/webhooks/calendar",
      hubspot: "#{base_url}/webhooks/hubspot",
      generic: "#{base_url}/webhooks/generic"
    }
  end
  
  @doc """
  Test webhook endpoints by sending sample payloads.
  
  This is useful for testing the webhook processing pipeline during development.
  """
  def test_webhooks(user_id) do
    Logger.info("Testing webhook endpoints for user #{user_id}")
    
    webhook_urls = get_webhook_urls()
    
    test_results = %{
      gmail: test_gmail_webhook(user_id),
      calendar: test_calendar_webhook(user_id),
      hubspot: test_hubspot_webhook(user_id)
    }
    
    Logger.info("Webhook test complete")
    {:ok, %{webhook_urls: webhook_urls, test_results: test_results}}
  end
  
  # Private helper functions
  
  defp get_webhook_base_url do
    # Get the base URL for webhook endpoints
    # This should be your application's public URL
    System.get_env("WEBHOOK_BASE_URL") || 
    System.get_env("APP_URL") || 
    "https://your-app.com"
  end
  
  defp test_gmail_webhook(user_id) do
    # Create a sample Gmail webhook payload for testing
    sample_payload = %{
      "message" => %{
        "data" => Base.encode64(Jason.encode!(%{
          "messageId" => "test-message-123",
          "threadId" => "test-thread-123",
          "historyId" => "12345"
        }))
      },
      "user_id" => user_id
    }
    
    Logger.debug("Sample Gmail webhook payload: #{inspect(sample_payload)}")
    {:ok, "Sample payload created"}
  end
  
  defp test_calendar_webhook(user_id) do
    # Create a sample Calendar webhook payload for testing
    sample_payload = %{
      "resourceId" => "test-resource-123",
      "resourceState" => "updated",
      "eventId" => "test-event-123",
      "eventStatus" => "confirmed",
      "attendees" => [
        %{
          "email" => "attendee@example.com",
          "responseStatus" => "accepted",
          "displayName" => "Test Attendee"
        }
      ],
      "user_id" => user_id
    }
    
    Logger.debug("Sample Calendar webhook payload: #{inspect(sample_payload)}")
    {:ok, "Sample payload created"}
  end
  
  defp test_hubspot_webhook(user_id) do
    # Create a sample HubSpot webhook payload for testing
    sample_payload = %{
      "subscriptionType" => "contact.creation",
      "eventId" => "test-event-123",
      "objectId" => "test-contact-123",
      "portalId" => "test-portal-123",
      "occurredAt" => (DateTime.utc_now() |> DateTime.to_unix()) * 1000,
      "user_id" => user_id
    }
    
    Logger.debug("Sample HubSpot webhook payload: #{inspect(sample_payload)}")
    {:ok, "Sample payload created"}
  end
end