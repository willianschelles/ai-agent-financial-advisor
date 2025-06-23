defmodule AiAgent.Google.GmailAPI do
  @moduledoc """
  Gmail API client for sending and managing emails.

  This module provides a wrapper around Gmail API calls using OAuth2 authentication.
  """

  require Logger

  @base_url "https://gmail.googleapis.com/gmail/v1"

  @doc """
  Send an email using Gmail API.

  ## Parameters
  - user: User struct with Google OAuth tokens
  - email_data: Map containing email details

  ## Returns
  - {:ok, message} on success
  - {:error, reason} on failure
  """
  def send_email(user, email_data) do
    IO.inspect(email_data, label: "Email Data")
    Logger.info("Sending email for user #{user.id}")

    case get_access_token(user) do
      {:ok, access_token} ->
        # Build the email message
        case build_email_message(email_data) do
          {:ok, raw_message} ->
            url = "#{@base_url}/users/me/messages/send"

            headers = [
              {"Authorization", "Bearer #{access_token}"},
              {"Content-Type", "application/json"}
            ]

            payload = %{
              raw: raw_message
            }

            Logger.debug("Sending email via Gmail API")

            IO.inspect(access_token, label: "Access Token")
            case Req.post(url, headers: headers, json: payload) do
              {:ok, %{status: 200, body: message}} ->
                Logger.info("Successfully sent email: #{message["id"]}")
                {:ok, message}

              {:ok, %{status: status, body: body}} ->
                Logger.error("Gmail API error: #{status} - #{inspect(body)}")
                {:error, "Gmail API error: #{status}"}

              {:error, reason} ->
                Logger.error("Failed to call Gmail API: #{inspect(reason)}")
                {:error, "Network error: #{inspect(reason)}"}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get user's email messages with optional query parameters.

  ## Parameters
  - user: User struct with Google OAuth tokens
  - params: Query parameters for filtering messages

  ## Returns
  - {:ok, [messages]} on success
  - {:error, reason} on failure
  """
  def list_messages(user, params \\ %{}) do
    Logger.info("Listing messages for user #{user.id}")

    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@base_url}/users/me/messages"

        headers = [
          {"Authorization", "Bearer #{access_token}"}
        ]

        # Build query parameters
        query_params = params
        |> Map.take([:q, :maxResults, :pageToken, :labelIds, :includeSpamTrash])
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Enum.into(%{})

        Logger.debug("Fetching messages with params: #{inspect(query_params)}")

        case Req.get(url, headers: headers, params: query_params) do
          {:ok, %{status: 200, body: %{"messages" => messages}}} ->
            Logger.info("Retrieved #{length(messages)} messages")
            {:ok, messages}

          {:ok, %{status: 200, body: %{"messages" => nil}}} ->
            {:ok, []}

          {:ok, %{status: status, body: body}} ->
            Logger.error("Gmail API error: #{status} - #{inspect(body)}")
            {:error, "Gmail API error: #{status}"}

          {:error, reason} ->
            Logger.error("Failed to call Gmail API: #{inspect(reason)}")
            {:error, "Network error: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get a specific email message by ID.

  ## Parameters
  - user: User struct with Google OAuth tokens
  - message_id: ID of the message to retrieve

  ## Returns
  - {:ok, message} on success
  - {:error, reason} on failure
  """
  def get_message(user, message_id) do
    Logger.info("Getting message #{message_id} for user #{user.id}")

    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@base_url}/users/me/messages/#{message_id}"

        headers = [
          {"Authorization", "Bearer #{access_token}"}
        ]

        case Req.get(url, headers: headers) do
          {:ok, %{status: 200, body: message}} ->
            Logger.info("Successfully retrieved message: #{message["id"]}")
            {:ok, message}

          {:ok, %{status: status, body: body}} ->
            Logger.error("Gmail API error: #{status} - #{inspect(body)}")
            {:error, "Gmail API error: #{status}"}

          {:error, reason} ->
            Logger.error("Failed to call Gmail API: #{inspect(reason)}")
            {:error, "Network error: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Reply to an email message.

  ## Parameters
  - user: User struct with Google OAuth tokens
  - message_id: ID of the message to reply to
  - reply_data: Map containing reply content

  ## Returns
  - {:ok, message} on success
  - {:error, reason} on failure
  """
  def reply_to_message(user, message_id, reply_data) do
    Logger.info("Replying to message #{message_id} for user #{user.id}")

    # First, get the original message to extract thread info and headers
    case get_message(user, message_id) do
      {:ok, original_message} ->
        # Build reply email with proper headers
        reply_email_data = build_reply_data(original_message, reply_data)

        # Send the reply
        send_email(user, reply_email_data)

      {:error, reason} ->
        {:error, "Failed to get original message: #{reason}"}
    end
  end

  # Private helper functions

  defp get_access_token(user) do
    case user.google_tokens do
      %{"access_token" => access_token} when is_binary(access_token) ->
        # TODO: Check if token is expired and refresh if needed
        {:ok, access_token}

      _ ->
        Logger.error("No valid Google access token found for user #{user.id}")
        {:error, "Gmail access not authorized"}
    end
  end

  defp build_email_message(email_data) do
    # Extract email components
    to_addresses = email_data[:to] || []
    cc_addresses = email_data[:cc] || []
    bcc_addresses = email_data[:bcc] || []
    subject = email_data[:subject] || ""
    body = email_data[:body] || ""

    # Validate required fields
    if Enum.empty?(to_addresses) or String.trim(subject) == "" or String.trim(body) == "" do
      {:error, "Missing required email fields (to, subject, body)"}
    else
      # Build email headers
      headers = [
        "To: #{Enum.join(to_addresses, ", ")}"
      ]

      headers = if Enum.empty?(cc_addresses) do
        headers
      else
        headers ++ ["Cc: #{Enum.join(cc_addresses, ", ")}"]
      end

      headers = if Enum.empty?(bcc_addresses) do
        headers
      else
        headers ++ ["Bcc: #{Enum.join(bcc_addresses, ", ")}"]
      end

      headers = headers ++ [
        "Subject: #{subject}",
        "Content-Type: text/plain; charset=UTF-8",
        ""
      ]

      # Combine headers and body
      email_content = Enum.join(headers, "\r\n") <> "\r\n" <> body

      # Base64 encode the email (URL-safe)
      encoded_email = email_content
      |> Base.encode64()
      |> String.replace("+", "-")
      |> String.replace("/", "_")
      |> String.replace("=", "")

      {:ok, encoded_email}
    end
  end

  defp build_reply_data(original_message, reply_data) do
    # Extract original message details
    original_headers = get_message_headers(original_message)
    original_subject = get_header_value(original_headers, "Subject")
    original_from = get_header_value(original_headers, "From")
    original_to = get_header_value(original_headers, "To")
    original_cc = get_header_value(original_headers, "Cc")
    thread_id = original_message["threadId"]

    # Build reply subject
    reply_subject = if String.starts_with?(original_subject, "Re:") do
      original_subject
    else
      "Re: #{original_subject}"
    end

    # Determine reply recipients
    # Reply to sender, and include original To/Cc if they were part of the conversation
    reply_to = [extract_email_from_header(original_from)]

    # TODO: Add logic to include other recipients based on reply-all preference

    %{
      to: reply_to |> Enum.reject(&is_nil/1),
      subject: reply_subject,
      body: reply_data[:body] || "",
      thread_id: thread_id
    }
  end

  defp get_message_headers(message) do
    case get_in(message, ["payload", "headers"]) do
      nil -> []
      headers -> headers
    end
  end

  defp get_header_value(headers, header_name) do
    case Enum.find(headers, fn h -> h["name"] == header_name end) do
      nil -> nil
      header -> header["value"]
    end
  end

  defp extract_email_from_header(header_value) when is_binary(header_value) do
    # Extract email from "Name <email@domain.com>" format
    email_regex = ~r/<([^>]+)>/

    case Regex.run(email_regex, header_value) do
      [_, email] -> email
      _ ->
        # If no angle brackets, check if the whole string is an email
        if String.contains?(header_value, "@") do
          String.trim(header_value)
        else
          nil
        end
    end
  end

  defp extract_email_from_header(_), do: nil
end
