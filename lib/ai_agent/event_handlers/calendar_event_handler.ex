defmodule AiAgent.EventHandlers.CalendarEventHandler do
  @moduledoc """
  Handles calendar events from Google Calendar webhooks and resumes waiting tasks.
  
  This module processes Google Calendar notifications for event responses,
  updates, and other calendar-related events that may trigger task resumption.
  """
  
  require Logger
  
  alias AiAgent.EventHandlers.WebhookHandler
  
  @doc """
  Handle a calendar event from Google Calendar webhook.
  
  ## Parameters
  - webhook_data: Calendar webhook payload
  - user_id: ID of the user whose calendar was updated
  
  ## Returns
  - {:ok, results} with resumed tasks
  - {:error, reason} if processing failed
  """
  def handle_calendar_event(webhook_data, user_id) do
    Logger.info("Handling calendar event for user #{user_id}")
    
    case parse_calendar_webhook(webhook_data) do
      {:ok, calendar_event} ->
        process_calendar_event(calendar_event, user_id)
      
      {:error, reason} ->
        Logger.error("Failed to parse calendar webhook: #{reason}")
        {:error, reason}
    end
  end
  
  @doc """
  Process a calendar event and resume any waiting tasks.
  """
  def process_calendar_event(calendar_event, user_id) do
    Logger.info("Processing calendar event for user #{user_id}: #{calendar_event.event_type}")
    
    event_data = %{
      event_id: calendar_event.event_id,
      event_type: calendar_event.event_type,
      attendee_responses: calendar_event.attendee_responses,
      event_status: calendar_event.event_status,
      updated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      raw_data: calendar_event
    }
    
    # Resume tasks based on the type of calendar event
    case calendar_event.event_type do
      "attendee_response" ->
        handle_attendee_response(event_data, user_id)
      
      "event_updated" ->
        handle_event_update(event_data, user_id)
      
      "event_cancelled" ->
        handle_event_cancellation(event_data, user_id)
      
      _ ->
        Logger.debug("Unhandled calendar event type: #{calendar_event.event_type}")
        {:ok, []}
    end
  end
  
  @doc """
  Set up Google Calendar push notifications for a user.
  """
  def setup_calendar_push_notifications(user) do
    Logger.info("Setting up Calendar push notifications for user #{user.id}")
    
    case mock_setup_calendar_watch(user) do
      {:ok, watch_response} ->
        Logger.info("Successfully set up Calendar watch for user #{user.id}")
        {:ok, watch_response}
      
      {:error, reason} ->
        Logger.error("Failed to set up Calendar watch for user #{user.id}: #{reason}")
        {:error, reason}
    end
  end
  
  @doc """
  Stop Google Calendar push notifications for a user.
  """
  def stop_calendar_push_notifications(user) do
    Logger.info("Stopping Calendar push notifications for user #{user.id}")
    
    case mock_stop_calendar_watch(user) do
      {:ok, _} ->
        Logger.info("Successfully stopped Calendar watch for user #{user.id}")
        {:ok, %{status: "stopped"}}
      
      {:error, reason} ->
        Logger.error("Failed to stop Calendar watch for user #{user.id}: #{reason}")
        {:error, reason}
    end
  end
  
  # Private helper functions
  
  defp parse_calendar_webhook(webhook_data) do
    # Parse Google Calendar webhook payload
    case webhook_data do
      %{"resourceId" => resource_id, "resourceState" => state} ->
        # Extract calendar event information
        calendar_event = %{
          resource_id: resource_id,
          resource_state: state,
          event_id: Map.get(webhook_data, "eventId"),
          event_type: determine_event_type(webhook_data),
          attendee_responses: extract_attendee_responses(webhook_data),
          event_status: Map.get(webhook_data, "eventStatus"),
          sync_token: Map.get(webhook_data, "syncToken")
        }
        
        {:ok, calendar_event}
      
      _ ->
        Logger.error("Invalid calendar webhook format: #{inspect(webhook_data)}")
        {:error, "Invalid webhook format"}
    end
  end
  
  defp determine_event_type(webhook_data) do
    # Determine the type of calendar event based on webhook data
    cond do
      Map.has_key?(webhook_data, "attendeeResponse") ->
        "attendee_response"
      
      Map.get(webhook_data, "eventStatus") == "cancelled" ->
        "event_cancelled"
      
      Map.get(webhook_data, "resourceState") == "updated" ->
        "event_updated"
      
      true ->
        "unknown"
    end
  end
  
  defp extract_attendee_responses(webhook_data) do
    # Extract attendee response information from webhook data
    case Map.get(webhook_data, "attendees") do
      nil -> []
      attendees when is_list(attendees) ->
        Enum.map(attendees, fn attendee ->
          %{
            email: Map.get(attendee, "email"),
            response_status: Map.get(attendee, "responseStatus"),
            display_name: Map.get(attendee, "displayName")
          }
        end)
      _ -> []
    end
  end
  
  defp handle_attendee_response(event_data, user_id) do
    Logger.info("Handling attendee response for user #{user_id}")
    
    # Look for tasks waiting for calendar responses
    WebhookHandler.resume_waiting_tasks("calendar_response", event_data, user_id, %{
      event_id: event_data.event_id
    })
  end
  
  defp handle_event_update(event_data, user_id) do
    Logger.info("Handling event update for user #{user_id}")
    
    # Resume tasks that might be waiting for event updates
    WebhookHandler.resume_waiting_tasks("calendar_response", event_data, user_id, %{
      event_id: event_data.event_id,
      event_type: "updated"
    })
  end
  
  defp handle_event_cancellation(event_data, user_id) do
    Logger.info("Handling event cancellation for user #{user_id}")
    
    # Resume tasks that might need to handle cancellations
    WebhookHandler.resume_waiting_tasks("calendar_response", event_data, user_id, %{
      event_id: event_data.event_id,
      event_type: "cancelled"
    })
  end
  
  # Mock functions for Calendar API integration
  
  defp mock_setup_calendar_watch(user) do
    Logger.debug("Mock: Setting up Calendar watch for user #{user.id}")
    
    {:ok, %{
      id: "calendar-watch-#{user.id}",
      resourceId: "calendar-resource-#{user.id}",
      expiration: (DateTime.add(DateTime.utc_now(), 7, :day) |> DateTime.to_unix()) * 1000
    }}
  end
  
  defp mock_stop_calendar_watch(user) do
    Logger.debug("Mock: Stopping Calendar watch for user #{user.id}")
    
    {:ok, %{status: "stopped"}}
  end
end