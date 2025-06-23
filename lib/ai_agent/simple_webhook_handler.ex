defmodule AiAgent.SimpleWebhookHandler do
  @moduledoc """
  Simplified webhook handler for email->calendar workflows.

  This processes Gmail webhooks and resumes waiting tasks.
  """

  require Logger
  alias AiAgent.SimpleWorkflowEngine

  @doc """
  Process a Gmail webhook and resume any waiting email->calendar tasks.

  ## Parameters
  - webhook_data: Gmail webhook payload
  - user_id: ID of the user who received the email

  ## Returns
  - {:ok, results} with list of resumed tasks
  - {:error, reason} if processing failed
  """
  def handle_gmail_webhook(webhook_data, user_id) do
    Logger.info("Processing Gmail webhook for user #{user_id}")

    case parse_gmail_webhook(webhook_data) do
      {:ok, email_data} ->
        # Check if this is an incoming email (not sent by us)
        if is_incoming_email?(email_data) do
          Logger.info("Processing incoming email for potential task resumption")

          # Enhance email data with more details if needed
          enhanced_email_data = enhance_email_data(email_data, webhook_data)

          # Resume any waiting workflows
          SimpleWorkflowEngine.resume_workflow_from_webhook(user_id, enhanced_email_data)
        else
          Logger.debug("Ignoring outgoing email")
          {:ok, []}
        end

      {:error, reason} ->
        Logger.error("Failed to parse Gmail webhook: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Parse Gmail webhook payload to extract email information.
  """
  def parse_gmail_webhook(webhook_data) do
    Logger.debug("Parsing Gmail webhook data: #{inspect(webhook_data)}")

    try do
      case webhook_data do
        %{"message" => %{"data" => encoded_data}} ->
          # Decode base64 message data
          decoded_data = Base.decode64!(encoded_data)
          message_data = Jason.decode!(decoded_data)

          IO.inspect(message_data, label: "Decoded Gmail Message Data")
          # Extract basic email information from the actual Gmail webhook format
          email_data = %{
            message_id: Map.get(message_data, "messageId"),
            thread_id: Map.get(message_data, "threadId"),
            history_id: Map.get(message_data, "historyId"),
            timestamp: Map.get(message_data, "timestamp"),
            email_address: Map.get(message_data, "emailAddress")
          }

          IO.inspect(email_data, label: "Extracted Email Data")
          {:ok, email_data}

        # Handle direct webhook format (for testing)
        %{"message_id" => message_id} = direct_data ->
          email_data = %{
            message_id: message_id,
            thread_id: Map.get(direct_data, "thread_id"),
            from: Map.get(direct_data, "from"),
            subject: Map.get(direct_data, "subject"),
            body: Map.get(direct_data, "body")
          }

          {:ok, email_data}

        _ ->
          Logger.error("Invalid Gmail webhook format: #{inspect(webhook_data)}")
          {:error, "Invalid webhook format"}
      end
    rescue
      error ->
        Logger.error("Failed to parse Gmail webhook: #{inspect(error)}")
        {:error, "Parsing error: #{inspect(error)}"}
    end
  end

  # Private helper functions

  defp is_incoming_email?(email_data) do
    IO.inspect(email_data, label: "Email Data for Incoming Check")
    # Simple heuristic: if we have a 'from' field, it's likely incoming
    # In a real implementation, you'd check against the user's email address
    Map.has_key?(email_data, :from) or
    Map.get(email_data, :labels, []) |> Enum.member?("INBOX")
  end

  defp enhance_email_data(email_data, webhook_data) do
    # Add additional fields that might be useful for task matching
    enhanced_data = Map.merge(email_data, %{
      received_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      webhook_processed_at: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    # If we don't have email details yet, fetch them using Gmail API
    if not Map.has_key?(enhanced_data, :from) do
      fetch_real_email_details(enhanced_data, webhook_data)
    else
      enhanced_data
    end
  end

  defp fetch_real_email_details(email_data, webhook_data) do
    # Extract user from webhook data
    user_id = extract_user_id_from_webhook_data(webhook_data)

    if user_id do
      case AiAgent.Repo.get(AiAgent.User, user_id) do
        nil ->
          Logger.error("User #{user_id} not found")
          email_data

        user ->
          # Get the history ID to find new messages
          history_id = Map.get(email_data, :history_id)

          if history_id do
            fetch_new_messages_from_history(email_data, user, history_id)
          else
            Logger.warning("No history_id in email data, cannot fetch Gmail details")
            email_data
          end
      end
    else
      Logger.warning("No user_id found in webhook data, cannot fetch Gmail details")
      email_data
    end
  end

  defp fetch_new_messages_from_history(email_data, user, history_id) do
    Logger.info("Fetching new messages from Gmail history #{history_id}")

    case AiAgent.Google.GmailAPI.get_history(user, history_id, %{historyTypes: ["messageAdded"]}) do
      {:ok, history_response} ->
        # Extract new messages from history
        case extract_new_messages_from_history_response(history_response) do
          [] ->
            Logger.info("No new messages found in history")
            email_data

          messages ->
            # Get details for the first new message (most recent)
            latest_message = List.first(messages)
            message_id = latest_message["id"]

            Logger.info("Found new message: #{message_id}, fetching details")
            fetch_message_details(email_data, user, message_id)
        end

      {:error, reason} ->
        Logger.error("Failed to get Gmail history: #{reason}")
        email_data
    end
  end

  defp fetch_message_details(email_data, user, message_id) do
    case AiAgent.Google.GmailAPI.get_message(user, message_id) do
      {:ok, message} ->
        # Extract email details from the message
        headers = get_in(message, ["payload", "headers"]) || []
        labels = Map.get(message, "labelIds", [])

        # Check if this is an incoming message (has INBOX label and not SENT)
        is_incoming = "INBOX" in labels and "SENT" not in labels

        if is_incoming do
          enhanced_data = Map.merge(email_data, %{
            message_id: message["id"],
            thread_id: message["threadId"],
            from: extract_header_value(headers, "From"),
            to: extract_header_value(headers, "To"),
            subject: extract_header_value(headers, "Subject"),
            date: extract_header_value(headers, "Date"),
            body: extract_message_body(message),
            labels: labels
          })

          Logger.info("Enhanced email data with real Gmail message details")
          enhanced_data
        else
          Logger.info("Message is outgoing, not processing")
          email_data
        end

      {:error, reason} ->
        Logger.error("Failed to get message details: #{reason}")
        email_data
    end
  end

  defp extract_new_messages_from_history_response(history_response) do
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

  defp extract_header_value(headers, header_name) do
    case Enum.find(headers, fn h -> h["name"] == header_name end) do
      nil -> nil
      header -> header["value"]
    end
  end

  defp extract_message_body(message) do
    # Extract message body from Gmail message payload
    case get_in(message, ["payload", "body", "data"]) do
      nil ->
        # Try to extract from parts for multipart messages
        extract_body_from_parts(get_in(message, ["payload", "parts"]))

      body_data ->
        # Decode base64 body data
        decode_gmail_body_data(body_data)
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
          data -> decode_gmail_body_data(data)
        end
    end
  end

  defp decode_gmail_body_data(body_data) do
    body_data
    |> String.replace("-", "+")
    |> String.replace("_", "/")
    |> Base.decode64()
    |> case do
      {:ok, decoded} -> decoded
      _ -> "Unable to decode message body"
    end
  end

  @doc """
  Test helper function to simulate webhook processing.
  """
  def simulate_email_reply(user_id, reply_data \\ %{}) do
    Logger.info("Simulating email reply for user #{user_id}")

    default_reply = %{
      message_id: "msg_#{:rand.uniform(1000000)}",
      thread_id: "thread_#{:rand.uniform(100000)}",
      from: "bianca.burginski@example.com",
      subject: "Re: Meeting Request",
      body: "Yes, I'm available tomorrow from 4-5pm. Looking forward to meeting with you!"
    }

    email_data = Map.merge(default_reply, reply_data)

    # Process as if it came from a webhook
    SimpleWorkflowEngine.resume_workflow_from_webhook(user_id, email_data)
  end
end
