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
    
    case setup_gmail_watch(user) do
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
    case stop_gmail_watch(user) do
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
  
  defp enhance_email_event(email_event, webhook_data) do
    # Extract user from webhook data to get their Gmail access
    user_id = extract_user_id_from_webhook_data(webhook_data)
    
    if user_id do
      case AiAgent.Repo.get(AiAgent.User, user_id) do
        nil ->
          Logger.error("User #{user_id} not found")
          email_event
        
        user ->
          # Get the history ID to find new messages
          history_id = Map.get(email_event, :history_id)
          
          if history_id do
            enhance_with_gmail_history(email_event, user, history_id)
          else
            Logger.warn("No history_id in email event, cannot fetch details")
            email_event
          end
      end
    else
      Logger.warn("No user_id found in webhook data")
      email_event
    end
  end
  
  defp enhance_with_gmail_history(email_event, user, history_id) do
    Logger.info("Enhancing email event with Gmail history from #{history_id}")
    
    case GmailAPI.get_history(user, history_id, %{historyTypes: ["messageAdded"]}) do
      {:ok, history_response} ->
        # Extract new messages from history
        case extract_new_messages_from_history(history_response) do
          [] ->
            Logger.info("No new messages found in history")
            email_event
          
          messages ->
            # Get details for the first new message (most recent)
            latest_message = List.first(messages)
            message_id = latest_message["id"]
            
            Logger.info("Found new message: #{message_id}")
            enhance_with_message_details(email_event, user, message_id)
        end
      
      {:error, reason} ->
        Logger.error("Failed to get Gmail history: #{reason}")
        email_event
    end
  end
  
  defp enhance_with_message_details(email_event, user, message_id) do
    case GmailAPI.get_message(user, message_id) do
      {:ok, message} ->
        # Extract email details from the message
        headers = get_in(message, ["payload", "headers"]) || []
        labels = Map.get(message, "labelIds", [])
        
        enhanced_event = Map.merge(email_event, %{
          message_id: message["id"],
          thread_id: message["threadId"],
          from: extract_header_value(headers, "From"),
          to: extract_header_value(headers, "To"),
          subject: extract_header_value(headers, "Subject"),
          date: extract_header_value(headers, "Date"),
          body: extract_message_body(message),
          labels: labels
        })
        
        Logger.info("Enhanced email event with real Gmail data")
        enhanced_event
      
      {:error, reason} ->
        Logger.error("Failed to get message details: #{reason}")
        email_event
    end
  end
  
  defp extract_new_messages_from_history(history_response) do
    case Map.get(history_response, "history") do
      nil -> []
      history_items ->
        history_items
        |> Enum.flat_map(fn item ->
          Map.get(item, "messagesAdded", [])
        end)
        |> Enum.map(fn item ->
          Map.get(item, "message")
        end)
        |> Enum.reject(&is_nil/1)
    end
  end
  
  defp extract_user_id_from_webhook_data(webhook_data) do
    # Try to extract user_id from webhook data
    case Map.get(webhook_data, "user_id") do
      nil ->
        # Try to extract from message data
        case get_in(webhook_data, ["message", "data"]) do
          nil -> nil
          encoded_data ->
            try do
              decoded_data = Base.decode64!(encoded_data)
              message_data = Jason.decode!(decoded_data)
              email_address = Map.get(message_data, "emailAddress")
              
              if email_address do
                # Look up user by email
                case AiAgent.Repo.get_by(AiAgent.User, email: email_address) do
                  nil -> nil
                  user -> user.id
                end
              else
                nil
              end
            rescue
              _ -> nil
            end
        end
      
      user_id -> user_id
    end
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
  
  # Real Gmail API implementations
  
  defp setup_gmail_watch(user) do
    # Real implementation of Gmail watch setup using Gmail API
    Logger.debug("Setting up Gmail watch for user #{user.id}")
    
    case GmailAPI.get_access_token(user) do
      {:ok, access_token} ->
        url = "https://gmail.googleapis.com/gmail/v1/users/me/watch"
        
        headers = [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]
        
        # Configure the watch request
        # You'll need to set up a Google Cloud Pub/Sub topic for this
        webhook_base_url = System.get_env("WEBHOOK_BASE_URL") || "https://your-app.com"
        topic_name = System.get_env("GMAIL_PUBSUB_TOPIC") || "projects/your-project/topics/gmail-notifications"
        
        payload = %{
          topicName: topic_name,
          labelIds: ["INBOX"],  # Only watch for inbox messages
          labelFilterAction: "include"
        }
        
        case Req.post(url, headers: headers, json: payload) do
          {:ok, %{status: 200, body: response}} ->
            Logger.info("Successfully set up Gmail watch for user #{user.id}")
            {:ok, response}
          
          {:ok, %{status: status, body: body}} ->
            Logger.error("Gmail watch setup failed: #{status} - #{inspect(body)}")
            {:error, "Gmail API error: #{status}"}
          
          {:error, reason} ->
            Logger.error("Failed to setup Gmail watch: #{inspect(reason)}")
            {:error, "Network error: #{inspect(reason)}"}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp stop_gmail_watch(user) do
    # Real implementation of Gmail watch stop
    Logger.debug("Stopping Gmail watch for user #{user.id}")
    
    case GmailAPI.get_access_token(user) do
      {:ok, access_token} ->
        url = "https://gmail.googleapis.com/gmail/v1/users/me/stop"
        
        headers = [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]
        
        case Req.post(url, headers: headers, json: %{}) do
          {:ok, %{status: 204}} ->
            Logger.info("Successfully stopped Gmail watch for user #{user.id}")
            {:ok, %{status: "stopped"}}
          
          {:ok, %{status: status, body: body}} ->
            Logger.error("Gmail watch stop failed: #{status} - #{inspect(body)}")
            {:error, "Gmail API error: #{status}"}
          
          {:error, reason} ->
            Logger.error("Failed to stop Gmail watch: #{inspect(reason)}")
            {:error, "Network error: #{inspect(reason)}"}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
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