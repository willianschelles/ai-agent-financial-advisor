defmodule AiAgentWeb.WebhookController do
  @moduledoc """
  Handles incoming webhooks from external services (Gmail, Calendar, HubSpot).

  This controller receives webhook notifications and processes them to resume
  waiting tasks in the workflow system.
  """

  use AiAgentWeb, :controller

  require Logger

  alias AiAgent.EventHandlers.WebhookHandler
  alias AiAgent.SimpleWebhookHandler
  alias AiAgent.Accounts
  alias AiAgent.Rules.RuleEngine

  @doc """
  Handle Gmail webhook notifications.

  Gmail sends notifications via Pub/Sub when messages are received.
  """
  def gmail(conn, params) do
    Logger.info("Received Gmail webhook: #{inspect(params)}")

    case extract_user_id_from_webhook(conn, params, "gmail") do
      {:ok, user_id} ->
        # Process proactive rules first
        proactive_results = process_proactive_rules(user_id, "email_received", params)
        
        # Try new simple webhook handler first
        case SimpleWebhookHandler.handle_gmail_webhook(params, user_id) do
          {:ok, results} ->
            Logger.info("Gmail webhook processed successfully with SimpleWebhookHandler: #{length(results)} tasks resumed")
            
            # Trigger incremental data refresh for new emails
            user = AiAgent.Accounts.get_user!(user_id)
            Task.start(fn ->
              AiAgent.Embeddings.RAG.refresh_user_data(user, %{
                clear_existing: false,
                gmail_opts: %{limit: 5} # Only recent messages
              })
            end)

            send_webhook_response(conn, :ok, %{
              status: "processed",
              tasks_resumed: length(results),
              proactive_rules_executed: proactive_results,
              handler: "simple"
            })

          {:error, reason} ->
            Logger.warning("SimpleWebhookHandler failed (#{reason}), trying original handler")
            
            # Fallback to original webhook handler
            case WebhookHandler.process_webhook("gmail", params, user_id) do
              {:ok, results} ->
                Logger.info("Gmail webhook processed successfully with original handler: #{length(results)} tasks resumed")

                send_webhook_response(conn, :ok, %{
                  status: "processed",
                  tasks_resumed: length(results),
                  proactive_rules_executed: proactive_results,
                  handler: "original"
                })

              {:error, reason2} ->
                Logger.error("Both webhook handlers failed: #{reason} / #{reason2}")
                send_webhook_response(conn, :unprocessable_entity, %{
                  error: "Both handlers failed", 
                  simple_error: reason,
                  original_error: reason2,
                  proactive_rules_executed: proactive_results
                })
            end
        end

      {:error, reason} ->
        Logger.error("Failed to extract user ID from Gmail webhook: #{reason}")
        send_webhook_response(conn, :bad_request, %{error: reason})
    end
  end

  @doc """
  Handle Google Calendar webhook notifications.

  Calendar sends notifications when events are updated or attendees respond.
  """
  def calendar(conn, params) do
    Logger.info("Received Calendar webhook: #{inspect(params)}")

    case extract_user_id_from_webhook(conn, params, "calendar") do
      {:ok, user_id} ->
        case WebhookHandler.process_webhook("calendar", params, user_id) do
          {:ok, results} ->
            Logger.info(
              "Calendar webhook processed successfully: #{length(results)} tasks resumed"
            )

            send_webhook_response(conn, :ok, %{
              status: "processed",
              tasks_resumed: length(results)
            })

          {:error, reason} ->
            Logger.error("Failed to process Calendar webhook: #{reason}")
            send_webhook_response(conn, :unprocessable_entity, %{error: reason})
        end

      {:error, reason} ->
        Logger.error("Failed to extract user ID from Calendar webhook: #{reason}")
        send_webhook_response(conn, :bad_request, %{error: reason})
    end
  end

  @doc """
  Handle HubSpot webhook notifications.

  HubSpot sends notifications when contacts, deals, or other objects are updated.
  """
  def hubspot(conn, params) do
    Logger.info("Received HubSpot webhook: #{inspect(params)}")

    case extract_user_id_from_webhook(conn, params, "hubspot") do
      {:ok, user_id} ->
        # Process proactive rules based on HubSpot event type
        trigger_type = determine_hubspot_trigger_type(params)
        proactive_results = process_proactive_rules(user_id, trigger_type, params)
        
        case WebhookHandler.process_webhook("hubspot", params, user_id) do
          {:ok, results} ->
            Logger.info(
              "HubSpot webhook processed successfully: #{length(results)} tasks resumed"
            )

            send_webhook_response(conn, :ok, %{
              status: "processed",
              tasks_resumed: length(results),
              proactive_rules_executed: proactive_results
            })

          {:error, reason} ->
            Logger.error("Failed to process HubSpot webhook: #{reason}")
            send_webhook_response(conn, :unprocessable_entity, %{
              error: reason,
              proactive_rules_executed: proactive_results
            })
        end

      {:error, reason} ->
        Logger.error("Failed to extract user ID from HubSpot webhook: #{reason}")
        send_webhook_response(conn, :bad_request, %{error: reason})
    end
  end

  @doc """
  Generic webhook endpoint for testing and other services.
  """
  def generic(conn, params) do
    Logger.info("Received generic webhook: #{inspect(params)}")

    webhook_type = Map.get(params, "type", "unknown")
    user_id = Map.get(params, "user_id")

    if user_id do
      case WebhookHandler.process_webhook(webhook_type, params, user_id) do
        {:ok, results} ->
          send_webhook_response(conn, :ok, %{status: "processed", tasks_resumed: length(results)})

        {:error, reason} ->
          send_webhook_response(conn, :unprocessable_entity, %{error: reason})
      end
    else
      send_webhook_response(conn, :bad_request, %{error: "user_id required"})
    end
  end

  # Private helper functions

  defp extract_user_id_from_webhook(conn, params, service) do
    # Try multiple methods to extract user ID from webhook
    user_id = extract_user_id_by_method(conn, params, service)

    case user_id do
      nil ->
        {:error, "Could not determine user ID from webhook"}

      user_id when is_integer(user_id) or is_binary(user_id) ->
        # Validate that user exists
        try do
          _user = Accounts.get_user!(user_id)
          {:ok, user_id}
        rescue
          Ecto.NoResultsError ->
            {:error, "User not found"}

          error ->
            {:error, "Database error: #{inspect(error)}"}
        end
    end
  end

  defp extract_user_id_by_method(conn, params, service) do
    # Method 1: Check for explicit user_id in params
    case Map.get(params, "user_id") do
      nil ->
        # Method 2: Check custom headers (X-User-ID)
        case get_req_header(conn, "x-user-id") do
          [user_id] ->
            case Integer.parse(user_id) do
              {id, ""} -> id
              _ -> user_id
            end

          _ ->
            # Method 3: Service-specific extraction
            extract_user_id_from_service_data(params, service)
        end

      user_id ->
        case Integer.parse(to_string(user_id)) do
          {id, ""} -> id
          _ -> user_id
        end
    end
  end

  defp extract_user_id_from_service_data(params, service) do
    case service do
      "gmail" ->
        # For Gmail, we might need to look up user by email address
        # This would require a mapping table or user lookup
        extract_gmail_user_id(params)

      "calendar" ->
        # For Calendar, similar approach
        extract_calendar_user_id(params)

      "hubspot" ->
        # For HubSpot, might be in portal_id or similar
        extract_hubspot_user_id(params)

      _ ->
        nil
    end
  end

  def extract_gmail_user_id(params) do
    # Get the "message" part
    message = params["message"] || %{}
    IO.inspect(message, label: "Gmail Webhook Message")
    # Get the base64 data
    data_b64 = message["data"]

    # Decode base64 and parse JSON
    with {:ok, decoded_json} <- Base.decode64(data_b64) do
      # Now you have the Gmail address, look up your user
      decoded_json = Jason.decode!(decoded_json)
      IO.inspect(decoded_json, label: "Decoded Gmail JSON")
      email = Map.get(decoded_json, "emailAddress")
      IO.inspect(email, label: "Extracted Gmail email")
      user = AiAgent.Repo.get_by(AiAgent.User, email: email)
      if user, do: user.id, else: nil
    else
      _ -> nil
    end
  end

  defp extract_calendar_user_id(params) do
    # Similar to Gmail - extract calendar owner info and map to user
    _ = params
    nil
  end

  defp extract_hubspot_user_id(params) do
    # Extract portal_id or other HubSpot identifiers and map to user
    case Map.get(params, "portalId") do
      nil ->
        nil

      portal_id ->
        # You'd need a lookup table: portal_id -> user_id
        # For now returning nil
        _ = portal_id
        nil
    end
  end

  defp send_webhook_response(conn, status, data) do
    conn
    |> put_status(status)
    |> json(data)
  end

  defp process_proactive_rules(user_id, trigger_type, event_data) do
    case RuleEngine.process_event(user_id, trigger_type, event_data) do
      {:ok, results} ->
        Logger.info("Processed #{length(results)} proactive rules for user #{user_id}")
        results
      
      {:error, reason} ->
        Logger.error("Failed to process proactive rules: #{reason}")
        []
    end
  end

  defp determine_hubspot_trigger_type(params) do
    # HubSpot webhooks contain subscription data that indicates the object type
    case get_in(params, ["subscriptionType"]) do
      "contact.creation" -> "hubspot_contact_created"
      "contact.propertyChange" -> "hubspot_contact_updated"
      "engagement.creation" -> "hubspot_note_created"
      _ -> "hubspot_contact_created" # default fallback
    end
  end
end
