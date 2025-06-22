defmodule AiAgent.Embeddings.DataIngestion do
  @moduledoc """
  Data ingestion module for importing emails and HubSpot data into the vector store.
  Handles fetching data from external APIs and storing with embeddings.
  """

  require Logger

  alias AiAgent.Embeddings.VectorStore
  alias AiAgent.User

  @doc """
  Ingest Gmail messages for a user and store them with embeddings.

  ## Parameters
  - user: User struct with google_tokens
  - opts: Options map with optional keys:
    - :limit - Number of messages to fetch (default: 50)
    - :query - Gmail search query (default: "-in:sent")
    - :include_sent - Whether to include sent messages (default: false)

  ## Returns
  - {:ok, ingested_count} on success
  - {:error, reason} on failure
  """
  def ingest_gmail_messages(user, opts \\ %{}) do
    limit = Map.get(opts, :limit, 50)
    # Exclude sent by default
    query = Map.get(opts, :query, "-in:sent")
    include_sent = Map.get(opts, :include_sent, false)

    with {:ok, access_token} <- get_google_access_token(user),
         {:ok, messages} <- fetch_gmail_messages(access_token, limit, query) do
      IO.inspect(messages, label: "Fetched Gmail Messages")
      # Convert messages to document format
      limited_messages = Enum.take(messages, 3)

      documents =
        limited_messages
        |> Enum.map(&gmail_message_to_document/1)
        |> Enum.filter(fn doc ->
          # Filter out sent messages if not requested
          include_sent || !String.contains?(doc.source, "sent")
        end)

      case VectorStore.store_documents_batch(user, documents) do
        {:ok, stored_docs} ->
          count = length(stored_docs)
          Logger.info("Ingested #{count} Gmail messages for user #{user.id}")
          {:ok, count}

        {:error, reason} ->
          Logger.error("Failed to store Gmail messages: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.error("Failed to ingest Gmail messages: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Ingest HubSpot contacts and notes for a user.

  ## Parameters
  - user: User struct with hubspot_tokens
  - opts: Options map with optional keys:
    - :include_contacts - Whether to include contact info (default: true)
    - :include_notes - Whether to include notes (default: true)
    - :limit - Number of records to fetch per type (default: 100)

  ## Returns
  - {:ok, ingested_count} on success
  - {:error, reason} on failure
  """
  def ingest_hubspot_data(user, opts \\ %{}) do
    include_contacts = Map.get(opts, :include_contacts, true)
    include_notes = Map.get(opts, :include_notes, true)
    limit = Map.get(opts, :limit, 100)

    with {:ok, access_token} <- get_hubspot_access_token(user) do
      documents = []
      IO.inspect(access_token, label: "HubSpot Access Token")
      # Fetch contacts if requested
      documents =
        if include_contacts do
          case fetch_hubspot_contacts(access_token, limit) do
            {:ok, contacts} ->
              contact_docs = Enum.map(contacts, &hubspot_contact_to_document/1)
              documents ++ contact_docs

            {:error, reason} ->
              Logger.warning("Failed to fetch HubSpot contacts: #{inspect(reason)}")
              documents
          end
        else
          documents
        end

      # Fetch notes if requested
      documents =
        if include_notes do
          case fetch_hubspot_notes(access_token, limit) do
            {:ok, notes} ->
              note_docs = Enum.map(notes, &hubspot_note_to_document/1)
              documents ++ note_docs

            {:error, reason} ->
              Logger.warning("Failed to fetch HubSpot notes: #{inspect(reason)}")
              documents
          end
        else
          documents
        end

      if Enum.empty?(documents) do
        {:ok, 0}
      else
        case VectorStore.store_documents_batch(user, documents) do
          {:ok, stored_docs} ->
            count = length(stored_docs)
            Logger.info("Ingested #{count} HubSpot records for user #{user.id}")
            {:ok, count}

          {:error, reason} ->
            Logger.error("Failed to store HubSpot data: #{inspect(reason)}")
            {:error, reason}
        end
      end
    else
      {:error, reason} ->
        Logger.error("Failed to ingest HubSpot data: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Full ingestion for a user - both Gmail and HubSpot data.

  ## Parameters
  - user: User struct with both google_tokens and hubspot_tokens
  - opts: Combined options for both Gmail and HubSpot ingestion

  ## Returns
  - {:ok, %{gmail: count, hubspot: count}} on success
  - {:error, reason} on failure
  """
  def ingest_all_data(user, opts \\ %{}) do
    gmail_opts = Map.get(opts, :gmail, %{})
    hubspot_opts = Map.get(opts, :hubspot, %{})

    results = %{gmail: 0, hubspot: 0}

    # Ingest Gmail if tokens available
    results =
      if user.google_tokens do
        case ingest_gmail_messages(user, gmail_opts) do
          {:ok, count} ->
            Map.put(results, :gmail, count)

          {:error, reason} ->
            Logger.warning("Gmail ingestion failed: #{inspect(reason)}")
            results
        end
      else
        results
      end

    # Ingest HubSpot if tokens available
    results =
      if user.hubspot_tokens do
        case ingest_hubspot_data(user, hubspot_opts) do
          {:ok, count} ->
            Map.put(results, :hubspot, count)

          {:error, reason} ->
            Logger.warning("HubSpot ingestion failed: #{inspect(reason)}")
            results
        end
      else
        results
      end

    total = results.gmail + results.hubspot
    Logger.info("Full ingestion complete for user #{user.id}: #{total} total documents")
    {:ok, results}
  end

  # Private functions for Gmail integration

  defp get_google_access_token(%User{google_tokens: nil}), do: {:error, "No Google tokens"}

  defp get_google_access_token(%User{google_tokens: tokens}) do
    case tokens["access_token"] || tokens[:access_token] do
      nil -> {:error, "No Google access token"}
      token -> {:ok, token}
    end
  end

  defp fetch_gmail_messages(access_token, limit, query) do
    headers = [{"Authorization", "Bearer #{access_token}"}]

    # First, get message IDs
    list_url = "https://gmail.googleapis.com/gmail/v1/users/me/messages"
    params = %{maxResults: limit, q: query}

    case Req.get(list_url, headers: headers, params: params) do
      {:ok, %{status: 200, body: %{"messages" => message_list}}} ->
        # Fetch full message details
        messages =
          message_list
          |> Enum.take(limit)
          |> Enum.map(fn %{"id" => id} ->
            fetch_gmail_message_details(access_token, id)
          end)
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, msg} -> msg end)

        {:ok, messages}

      {:ok, %{status: status, body: body}} ->
        {:error, "Gmail API error: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp fetch_gmail_message_details(access_token, message_id) do
    headers = [{"Authorization", "Bearer #{access_token}"}]
    url = "https://gmail.googleapis.com/gmail/v1/users/me/messages/#{message_id}"

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: message}} ->
        {:ok, message}

      {:ok, %{status: status}} ->
        {:error, "Failed to fetch message #{message_id}: #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp gmail_message_to_document(message) do
    Logger.debug("Transforming Gmail message to document: #{inspect(message["id"])}")

    # Extract relevant fields from Gmail API response
    headers = get_in(message, ["payload", "headers"]) || []
    subject = get_header_value(headers, "Subject") || "No Subject"
    from = get_header_value(headers, "From") || "Unknown Sender"
    date = get_header_value(headers, "Date") || ""

    Logger.info("Gmail message details - Subject: #{subject}, From: #{from}, Date: #{date}")

    # Extract body text
    body = extract_message_body(message["payload"])

    Logger.debug(
      "Extracted body for message #{inspect(message["id"])}: #{String.slice(body, 0, 100)}..."
    )

    # Create content combining subject and body
    content = "Subject: #{subject}\n\n#{body}"

    Logger.debug(
      "Final document content for message #{inspect(message["id"])}: #{String.slice(content, 0, 100)}..."
    )

    %{
      content: content,
      source: from,
      type: "email"
    }

    # Extract relevant fields from Gmail API response
    headers = get_in(message, ["payload", "headers"]) || []
    subject = get_header_value(headers, "Subject") || "No Subject"
    from = get_header_value(headers, "From") || "Unknown Sender"
    date = get_header_value(headers, "Date") || ""

    # Extract body text
    body = extract_message_body(message["payload"])

    # Create content combining subject and body
    content = "Subject: #{subject}\n\n#{body}"

    %{
      content: content,
      source: from,
      type: "email"
    }
  end

  defp get_header_value(headers, name) do
    headers
    |> Enum.find(fn %{"name" => header_name} ->
      String.downcase(header_name) == String.downcase(name)
    end)
    |> case do
      %{"value" => value} -> value
      _ -> nil
    end
  end

  defp extract_message_body(payload) do
    cond do
      # Single part message
      payload["body"]["data"] ->
        decode_base64_body(payload["body"]["data"])

      # Multi-part message
      payload["parts"] ->
        payload["parts"]
        |> Enum.map(&extract_message_body/1)
        |> Enum.join("\n")

      # Nested parts
      true ->
        ""
    end
  end

  defp decode_base64_body(data) do
    data
    |> String.replace("-", "+")
    |> String.replace("_", "/")
    |> Base.decode64!(padding: false)
    |> String.replace(~r/\r\n|\r|\n/, " ")
    |> String.trim()
  rescue
    _ -> ""
  end

  # Private functions for HubSpot integration

  defp get_hubspot_access_token(%User{hubspot_tokens: nil}),
    do: {:error, "No HubSpot tokens - user needs to authenticate with HubSpot"}

  defp get_hubspot_access_token(%User{hubspot_tokens: tokens}) when is_map(tokens) do
    case tokens["access_token"] || tokens[:access_token] do
      nil ->
        Logger.error(
          "HubSpot token map missing access_token. Available keys: #{inspect(Map.keys(tokens))}"
        )

        {:error, "No HubSpot access token in stored map"}

      token when is_binary(token) ->
        # Check if token appears to be expired (if we have expiry info)
        case tokens["expires_at"] || tokens[:expires_at] do
          expires_at when is_integer(expires_at) ->
            current_time = System.system_time(:second)

            if expires_at < current_time do
              {:error,
               "HubSpot token appears to be expired (expires_at: #{expires_at}, current: #{current_time})"}
            else
              {:ok, token}
            end

          _ ->
            {:ok, token}
        end

      _ ->
        {:error, "HubSpot access token is not a string"}
    end
  end

  defp get_hubspot_access_token(%User{hubspot_tokens: token}) when is_binary(token) do
    if String.length(token) > 10 do
      {:ok, token}
    else
      {:error, "HubSpot token appears to be too short (#{String.length(token)} chars)"}
    end
  end

  defp get_hubspot_access_token(%User{hubspot_tokens: other}) do
    Logger.error("Unexpected HubSpot token format: #{inspect(other)}")
    {:error, "Unexpected HubSpot token format: #{inspect(other)}"}
  end

  defp fetch_hubspot_contacts(access_token, limit) do
    headers = [{"Authorization", "Bearer #{access_token}"}]
    url = "https://api.hubapi.com/crm/v3/objects/contacts"

    params = %{
      limit: limit,
      properties: "firstname,lastname,email,company,phone,notes_last_contacted"
    }

    Logger.info("Making HubSpot contacts API request to: #{url}")
    Logger.debug("Request headers: #{inspect(headers)}")
    Logger.debug("Request params: #{inspect(params)}")

    case Req.get(url, headers: headers, params: params) do
      {:ok, %{status: 200, body: %{"results" => contacts}}} ->
        Logger.info("Successfully fetched #{length(contacts)} HubSpot contacts")
        {:ok, contacts}

      {:ok, %{status: 401, body: body}} ->
        Logger.error("HubSpot authentication failed (401). Token may be invalid or expired.")
        Logger.error("Response body: #{inspect(body)}")

        error_msg =
          case body do
            %{"message" => message} -> message
            _ -> "Authentication failed"
          end

        {:error,
         "HubSpot authentication failed: #{error_msg}. Please re-authenticate with HubSpot."}

      {:ok, %{status: 403, body: body}} ->
        Logger.error("HubSpot access forbidden (403). Check scopes and permissions.")
        Logger.error("Response body: #{inspect(body)}")
        {:error, "HubSpot access forbidden: Check your app permissions and scopes"}

      {:ok, %{status: status, body: body}} ->
        Logger.error("HubSpot API error: #{status}")
        Logger.error("Response body: #{inspect(body)}")
        {:error, "HubSpot API error: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        Logger.error("Network error calling HubSpot API: #{inspect(reason)}")
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp fetch_hubspot_notes(access_token, limit) do
    headers = [{"Authorization", "Bearer #{access_token}"}]
    url = "https://api.hubapi.com/crm/v3/objects/notes"

    params = %{
      limit: limit,
      properties: "hs_note_body,hs_attachment_ids,hubspot_owner_id"
    }

    case Req.get(url, headers: headers, params: params) do
      {:ok, %{status: 200, body: %{"results" => notes}}} ->
        {:ok, notes}

      {:ok, %{status: status, body: body}} ->
        {:error, "HubSpot API error: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp hubspot_contact_to_document(contact) do
    props = contact["properties"] || %{}

    # Build contact information string
    name_parts = [props["firstname"], props["lastname"]]
    name = name_parts |> Enum.filter(& &1) |> Enum.join(" ")
    name = if name == "", do: "Unknown Contact", else: name

    content_parts = [
      "Contact: #{name}",
      props["email"] && "Email: #{props["email"]}",
      props["company"] && "Company: #{props["company"]}",
      props["phone"] && "Phone: #{props["phone"]}",
      props["notes_last_contacted"] && "Notes: #{props["notes_last_contacted"]}"
    ]

    content =
      content_parts
      |> Enum.filter(& &1)
      |> Enum.join("\n")

    %{
      content: content,
      source: "hubspot_contact",
      type: "hubspot_contact"
    }
  end

  defp hubspot_note_to_document(note) do
    props = note["properties"] || %{}
    body = props["hs_note_body"] || "Empty note"

    %{
      content: body,
      source: "hubspot_note",
      type: "hubspot_note"
    }
  end
end
