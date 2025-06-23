defmodule AiAgent.EventHandlers.EmailEventHandler do
  @moduledoc """
  Handles email events from Gmail webhooks and resumes waiting tasks.
  
  This module processes Gmail push notifications and determines if any tasks
  are waiting for email replies that should be resumed.
  """
  
  require Logger
  
  alias AiAgent.EventHandlers.WebhookHandler
  alias AiAgent.Google.GmailAPI
  
  @doc """
  Handle an email event from Gmail webhook.
  
  ## Parameters
  - webhook_data: Gmail webhook payload
  - user_id: ID of the user who received the email
  
  ## Returns
  - {:ok, results} with resumed tasks
  - {:error, reason} if processing failed
  """
  def handle_email_event(webhook_data, user_id) do
    Logger.info("Handling email event for user #{user_id}")
    
    case parse_gmail_webhook(webhook_data) do
      {:ok, email_event} ->
        # Check if this is a new email (not sent by us)
        if is_incoming_email?(email_event) do
          process_incoming_email(email_event, user_id)
        else
          Logger.debug("Ignoring outgoing email event")
          {:ok, []}
        end
      
      {:error, reason} ->
        Logger.error("Failed to parse Gmail webhook: #{reason}")
        {:error, reason}
    end
  end
  
  @doc """
  Process an incoming email and resume any waiting tasks.
  """
  def process_incoming_email(email_event, user_id) do
    Logger.info("Processing incoming email for user #{user_id}")
    
    # Extract relevant information from the email
    event_data = %{
      message_id: email_event.message_id,
      thread_id: email_event.thread_id,
      from: email_event.from,
      subject: email_event.subject,
      body: email_event.body,
      received_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    # Look for tasks waiting for email replies
    WebhookHandler.resume_waiting_tasks("email_reply", event_data, user_id, %{
      thread_id: email_event.thread_id
    })
  end
  
  @doc """
  Set up Gmail push notifications for a user.
  
  This configures Gmail to send webhook notifications when new emails arrive.
  """
  def setup_gmail_push_notifications(user) do
    Logger.info("Setting up Gmail push notifications for user #{user.id}")
    
    # TODO: Implement Gmail Push API setup
    # This would use the Gmail API to set up push notifications to our webhook endpoint
    
    # Example of what this would look like:
    # 1. Create a Pub/Sub topic
    # 2. Subscribe to Gmail changes using watch() API
    # 3. Configure webhook endpoint to receive notifications
    
    case mock_setup_gmail_watch(user) do
      {:ok, watch_response} ->
        Logger.info("Successfully set up Gmail watch for user #{user.id}")
        {:ok, watch_response}
      
      {:error, reason} ->
        Logger.error("Failed to set up Gmail watch for user #{user.id}: #{reason}")
        {:error, reason}
    end
  end
  
  @doc """
  Stop Gmail push notifications for a user.
  """
  def stop_gmail_push_notifications(user) do
    Logger.info("Stopping Gmail push notifications for user #{user.id}")
    
    # TODO: Implement Gmail watch stop
    case mock_stop_gmail_watch(user) do
      {:ok, _} ->
        Logger.info("Successfully stopped Gmail watch for user #{user.id}")
        {:ok, %{status: "stopped"}}
      
      {:error, reason} ->
        Logger.error("Failed to stop Gmail watch for user #{user.id}: #{reason}")
        {:error, reason}
    end
  end
  
  # Private helper functions
  
  defp parse_gmail_webhook(webhook_data) do
    # Parse the Gmail webhook payload
    # Gmail sends Pub/Sub messages with message data
    
    case webhook_data do
      %{"message" => %{"data" => encoded_data}} ->
        try do
          # Decode base64 message data
          decoded_data = Base.decode64!(encoded_data)
          message_data = Jason.decode!(decoded_data)
          
          # Extract email information
          email_event = %{
            message_id: Map.get(message_data, "messageId"),
            thread_id: Map.get(message_data, "threadId"),
            history_id: Map.get(message_data, "historyId"),
            timestamp: Map.get(message_data, "timestamp")
          }
          
          # Fetch additional email details if needed
          enhanced_event = enhance_email_event(email_event, webhook_data)
          
          {:ok, enhanced_event}
        rescue
          error ->
            Logger.error("Failed to parse Gmail webhook data: #{inspect(error)}")
            {:error, "Invalid webhook data format"}
        end
      
      _ ->
        Logger.error("Invalid Gmail webhook format: #{inspect(webhook_data)}")
        {:error, "Invalid webhook format"}
    end
  end
  
  defp enhance_email_event(email_event, _webhook_data) do
    # In a real implementation, we would fetch additional email details
    # using the Gmail API with the message_id
    
    # For now, return mock enhanced data
    Map.merge(email_event, %{
      from: "sender@example.com",
      subject: "Email Reply",
      body: "This is a reply to your email...",
      labels: ["INBOX", "UNREAD"]
    })
  end
  
  defp is_incoming_email?(email_event) do
    # Determine if this is an incoming email (not sent by us)
    # This could be based on:
    # - Checking if the sender is not the user
    # - Checking email labels (SENT vs INBOX)
    # - Checking message headers
    
    # For now, simple heuristic based on labels
    labels = Map.get(email_event, :labels, [])
    "INBOX" in labels and "SENT" not in labels
  end
  
  # Mock functions for Gmail API integration
  # In production, these would use the actual Gmail API
  
  defp mock_setup_gmail_watch(user) do
    # Mock implementation of Gmail watch setup
    Logger.debug("Mock: Setting up Gmail watch for user #{user.id}")
    
    # Simulate successful watch setup
    {:ok, %{
      historyId: "123456789",
      expiration: (DateTime.add(DateTime.utc_now(), 7, :day) |> DateTime.to_unix()) * 1000
    }}
  end
  
  defp mock_stop_gmail_watch(user) do
    # Mock implementation of Gmail watch stop
    Logger.debug("Mock: Stopping Gmail watch for user #{user.id}")
    
    {:ok, %{status: "stopped"}}
  end
  
  @doc """
  Fetch full email details using Gmail API.
  
  This would be called when we need more information about an email
  than what's provided in the webhook notification.
  """
  def fetch_email_details(user, message_id) do
    Logger.debug("Fetching email details for message #{message_id}")
    
    case GmailAPI.get_message(user, message_id) do
      {:ok, message} ->
        # Extract relevant information from the full message
        email_details = %{
          message_id: message["id"],
          thread_id: message["threadId"],
          subject: extract_header_value(message, "Subject"),
          from: extract_header_value(message, "From"),
          to: extract_header_value(message, "To"),
          date: extract_header_value(message, "Date"),
          body: extract_message_body(message)
        }
        
        {:ok, email_details}
      
      {:error, reason} ->
        Logger.error("Failed to fetch email details: #{reason}")
        {:error, reason}
    end
  end
  
  defp extract_header_value(message, header_name) do
    headers = get_in(message, ["payload", "headers"]) || []
    
    case Enum.find(headers, fn h -> h["name"] == header_name end) do
      nil -> nil
      header -> header["value"]
    end
  end
  
  defp extract_message_body(message) do
    # Extract message body from Gmail message payload
    # This handles multipart messages and different encodings
    
    case get_in(message, ["payload", "body", "data"]) do
      nil ->
        # Try to extract from parts for multipart messages
        extract_body_from_parts(get_in(message, ["payload", "parts"]))
      
      body_data ->
        # Decode base64 body data
        body_data
        |> String.replace("-", "+")
        |> String.replace("_", "/")
        |> Base.decode64()
        |> case do
          {:ok, decoded} -> decoded
          _ -> "Unable to decode message body"
        end
    end
  end
  
  defp extract_body_from_parts(nil), do: "No message body found"
  defp extract_body_from_parts(parts) when is_list(parts) do
    # Find the text/plain part
    text_part = Enum.find(parts, fn part ->
      get_in(part, ["mimeType"]) == "text/plain"
    end)
    
    case text_part do
      nil -> "No text content found"
      part -> 
        case get_in(part, ["body", "data"]) do
          nil -> "No body data found"
          data -> 
            data
            |> String.replace("-", "+")
            |> String.replace("_", "/")
            |> Base.decode64()
            |> case do
              {:ok, decoded} -> decoded
              _ -> "Unable to decode body"
            end
        end
    end
  end
end