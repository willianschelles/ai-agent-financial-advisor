defmodule AiAgent.EventHandlers.WebhookHandler do
  @moduledoc """
  Webhook handler for external events that can resume waiting tasks.

  This module processes incoming webhooks from Gmail, Google Calendar, HubSpot,
  and other external services to resume tasks that are waiting for external events.
  """

  require Logger

  alias AiAgent.{TaskManager, WorkflowEngine}
  alias AiAgent.EventHandlers.{EmailEventHandler, CalendarEventHandler, HubSpotEventHandler}

  @doc """
  Process an incoming webhook and resume any waiting tasks.

  ## Parameters
  - webhook_type: Type of webhook (gmail, calendar, hubspot, etc.)
  - webhook_data: Data from the webhook payload
  - user_id: ID of the user (extracted from webhook data or headers)

  ## Returns
  - {:ok, results} with list of resumed tasks
  - {:error, reason} if processing failed
  """
  def process_webhook(webhook_type, webhook_data, user_id) do
    Logger.info("Processing #{webhook_type} webhook for user #{user_id}")

    case webhook_type do
      "gmail" ->
        EmailEventHandler.handle_email_event(webhook_data, user_id)

      "calendar" ->
        CalendarEventHandler.handle_calendar_event(webhook_data, user_id)

      "hubspot" ->
        HubSpotEventHandler.handle_hubspot_event(webhook_data, user_id)

      _ ->
        Logger.warn("Unknown webhook type: #{webhook_type}")
        {:error, "Unknown webhook type"}
    end
  end

  @doc """
  Register webhook URLs for a user with external services.

  This sets up webhooks with Gmail, Calendar, and HubSpot to receive notifications
  when events occur that might resume waiting tasks.
  """
  def register_webhooks(user) do
    Logger.info("Registering webhooks for user #{user.id}")

    base_url = get_webhook_base_url()

    results = [
      register_gmail_webhook(user, base_url),
      register_calendar_webhook(user, base_url),
      register_hubspot_webhook(user, base_url)
    ]

    successful = Enum.count(results, fn {status, _} -> status == :ok end)
    total = length(results)

    Logger.info("Registered #{successful}/#{total} webhooks for user #{user.id}")

    {:ok, %{successful: successful, total: total, results: results}}
  end

  @doc """
  Unregister webhooks for a user.
  """
  def unregister_webhooks(user) do
    Logger.info("Unregistering webhooks for user #{user.id}")

    # TODO: Implement webhook unregistration
    {:ok, %{message: "Webhooks unregistered"}}
  end

  @doc """
  Find and resume tasks that are waiting for a specific type of event.

  ## Parameters
  - event_type: Type of event that occurred
  - event_data: Data from the event
  - user_id: ID of the user
  - filter_criteria: Additional criteria to match waiting tasks

  ## Returns
  - {:ok, resumed_tasks} list of tasks that were resumed
  - {:error, reason} if processing failed
  """
  def resume_waiting_tasks(event_type, event_data, user_id, filter_criteria \\ %{}) do
    Logger.info("Looking for tasks waiting for #{event_type} for user #{user_id}")

    # Find tasks waiting for this type of event
    waiting_tasks = TaskManager.get_waiting_tasks(user_id, event_type)

    # Filter tasks based on criteria
    matching_tasks = filter_matching_tasks(waiting_tasks, event_data, filter_criteria)

    Logger.info("Found #{length(matching_tasks)} tasks to resume")

    # Resume each matching task
    results = Enum.map(matching_tasks, fn task ->
      case WorkflowEngine.resume_workflow(task, event_type, event_data, %{id: user_id}) do
        {:ok, result} ->
          Logger.info("Successfully resumed task #{task.id}")
          {:ok, task.id, result}

        {:waiting, updated_task} ->
          Logger.info("Task #{task.id} is still waiting after resumption")
          {:waiting, task.id, updated_task}

        {:error, reason} ->
          Logger.error("Failed to resume task #{task.id}: #{reason}")
          {:error, task.id, reason}
      end
    end)

    {:ok, results}
  end

  # Private helper functions

  defp register_gmail_webhook(user, base_url) do
    webhook_url = "#{base_url}/webhooks/gmail"

    # TODO: Implement Gmail Push notification setup
    # This would use Gmail API to set up push notifications
    Logger.debug("Would register Gmail webhook: #{webhook_url}")

    {:ok, %{service: "gmail", url: webhook_url, status: "registered"}}
  end

  defp register_calendar_webhook(user, base_url) do
    webhook_url = "#{base_url}/webhooks/calendar"

    # TODO: Implement Calendar webhook setup
    # This would use Calendar API to set up event notifications
    Logger.debug("Would register Calendar webhook: #{webhook_url}")

    {:ok, %{service: "calendar", url: webhook_url, status: "registered"}}
  end

  defp register_hubspot_webhook(user, base_url) do
    webhook_url = "#{base_url}/webhooks/hubspot"

    # TODO: Implement HubSpot webhook setup
    # This would use HubSpot API to set up contact/deal notifications
    Logger.debug("Would register HubSpot webhook: #{webhook_url}")

    {:ok, %{service: "hubspot", url: webhook_url, status: "registered"}}
  end

  defp filter_matching_tasks(waiting_tasks, event_data, filter_criteria) do
    Enum.filter(waiting_tasks, fn task ->
      matches_task_criteria?(task, event_data, filter_criteria)
    end)
  end

  defp matches_task_criteria?(task, event_data, filter_criteria) do
    # Check if the event data matches what the task is waiting for
    waiting_data = task.waiting_for_data

    # Basic matching logic - can be extended for more complex scenarios
    case task.waiting_for do
      "email_reply" ->
        matches_email_criteria?(waiting_data, event_data, filter_criteria)

      "calendar_response" ->
        matches_calendar_criteria?(waiting_data, event_data, filter_criteria)

      "webhook_event" ->
        matches_webhook_criteria?(waiting_data, event_data, filter_criteria)

      _ ->
        false
    end
  end

  defp matches_email_criteria?(waiting_data, event_data, _filter_criteria) do
    # Check if the email event matches what we're waiting for
    waiting_message_id = Map.get(waiting_data, "message_id")
    event_thread_id = Map.get(event_data, "thread_id")
    event_message_id = Map.get(event_data, "message_id")

    # Match by thread ID or message ID
    (waiting_message_id && event_message_id && waiting_message_id == event_message_id) ||
    (event_thread_id && Map.get(waiting_data, "thread_id") == event_thread_id)
  end

  defp matches_calendar_criteria?(waiting_data, event_data, _filter_criteria) do
    # Check if the calendar event matches what we're waiting for
    waiting_event_id = Map.get(waiting_data, "event_id")
    event_id = Map.get(event_data, "event_id")

    waiting_event_id && event_id && waiting_event_id == event_id
  end

  defp matches_webhook_criteria?(waiting_data, event_data, filter_criteria) do
    # Generic webhook matching based on provided criteria
    Enum.all?(filter_criteria, fn {key, value} ->
      Map.get(event_data, key) == value
    end)
  end

  defp get_webhook_base_url do
    # Get the base URL for webhook endpoints
    # This would typically be configured via environment variables
    System.get_env("WEBHOOK_BASE_URL") || "https://your-app.com"
  end
end
