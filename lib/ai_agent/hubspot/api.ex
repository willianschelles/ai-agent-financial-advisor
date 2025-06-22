defmodule AiAgent.HubSpot.API do
  @moduledoc """
  HubSpot API client for CRM operations.

  This module provides a wrapper around HubSpot API calls using OAuth2 authentication.
  """

  require Logger

  @base_url "https://api.hubapi.com"

  @doc """
  Create a new contact in HubSpot.

  ## Parameters
  - user: User struct with HubSpot OAuth tokens
  - contact_data: Map containing contact details

  ## Returns
  - {:ok, contact} on success
  - {:error, reason} on failure
  """
  def create_contact(user, contact_data) do
    Logger.info("Creating HubSpot contact for user #{user.id}")

    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@base_url}/crm/v3/objects/contacts"

        headers = [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]

        Logger.debug("Sending contact creation request to HubSpot")

        case Req.post(url, headers: headers, json: contact_data) do
          {:ok, %{status: 201, body: contact}} ->
            Logger.info("Successfully created HubSpot contact: #{contact["id"]}")
            {:ok, contact}

          {:ok, %{status: status, body: body}} ->
            Logger.error("HubSpot API error: #{status} - #{inspect(body)}")
            {:error, "HubSpot API error: #{status}"}

          {:error, reason} ->
            Logger.error("Failed to call HubSpot API: #{inspect(reason)}")
            {:error, "Network error: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Update a contact by ID.

  ## Parameters
  - user: User struct with HubSpot OAuth tokens
  - contact_id: HubSpot contact ID
  - contact_data: Map containing updated contact details

  ## Returns
  - {:ok, contact} on success
  - {:error, reason} on failure
  """
  def update_contact_by_id(user, contact_id, contact_data) do
    Logger.info("Updating HubSpot contact #{contact_id} for user #{user.id}")

    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@base_url}/crm/v3/objects/contacts/#{contact_id}"

        headers = [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]

        case Req.patch(url, headers: headers, json: contact_data) do
          {:ok, %{status: 200, body: contact}} ->
            Logger.info("Successfully updated HubSpot contact: #{contact["id"]}")
            {:ok, contact}

          {:ok, %{status: status, body: body}} ->
            Logger.error("HubSpot API error: #{status} - #{inspect(body)}")
            {:error, "HubSpot API error: #{status}"}

          {:error, reason} ->
            Logger.error("Failed to call HubSpot API: #{inspect(reason)}")
            {:error, "Network error: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Update a contact by email address.

  ## Parameters
  - user: User struct with HubSpot OAuth tokens
  - email: Contact's email address
  - contact_data: Map containing updated contact details

  ## Returns
  - {:ok, contact} on success
  - {:error, reason} on failure
  """
  def update_contact_by_email(user, email, contact_data) do
    Logger.info("Updating HubSpot contact by email #{email} for user #{user.id}")

    # First find the contact by email
    case get_contact_by_email(user, email) do
      {:ok, contact} ->
        update_contact_by_id(user, contact["id"], contact_data)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get a contact by email address.

  ## Parameters
  - user: User struct with HubSpot OAuth tokens
  - email: Contact's email address

  ## Returns
  - {:ok, contact} on success
  - {:error, reason} on failure
  """
  def get_contact_by_email(user, email) do
    Logger.info("Getting HubSpot contact by email #{email} for user #{user.id}")

    case get_access_token(user) do
      {:ok, access_token} ->
        # Use the search API to find contact by email
        url = "#{@base_url}/crm/v3/objects/contacts/search"

        headers = [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]

        search_data = %{
          filterGroups: [
            %{
              filters: [
                %{
                  propertyName: "email",
                  operator: "EQ",
                  value: email
                }
              ]
            }
          ],
          properties: ["email", "firstname", "lastname", "company", "jobtitle"],
          limit: 1
        }

        case Req.post(url, headers: headers, json: search_data) do
          {:ok, %{status: 200, body: %{"results" => [contact | _]}}} ->
            Logger.info("Found HubSpot contact by email: #{contact["id"]}")
            {:ok, contact}

          {:ok, %{status: 200, body: %{"results" => []}}} ->
            Logger.info("No HubSpot contact found with email: #{email}")
            {:error, "Contact not found"}

          {:ok, %{status: status, body: body}} ->
            Logger.error("HubSpot API error: #{status} - #{inspect(body)}")
            {:error, "HubSpot API error: #{status}"}

          {:error, reason} ->
            Logger.error("Failed to call HubSpot API: #{inspect(reason)}")
            {:error, "Network error: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for contacts in HubSpot.

  ## Parameters
  - user: User struct with HubSpot OAuth tokens
  - search_data: Map containing search parameters

  ## Returns
  - {:ok, [contacts]} on success
  - {:error, reason} on failure
  """
  def search_contacts(user, search_data) do
    Logger.info("Searching HubSpot contacts for user #{user.id}")

    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@base_url}/crm/v3/objects/contacts/search"

        headers = [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]

        # Build search request with text query
        request_data = %{
          query: search_data.query,
          limit: search_data.limit,
          properties:
            search_data.properties || ["email", "firstname", "lastname", "company", "jobtitle"]
        }

        case Req.post(url, headers: headers, json: request_data) do
          {:ok, %{status: 200, body: %{"results" => contacts}}} ->
            Logger.info("Found #{length(contacts)} HubSpot contacts")
            {:ok, contacts}

          {:ok, %{status: status, body: body}} ->
            Logger.error("HubSpot API error: #{status} - #{inspect(body)}")
            {:error, "HubSpot API error: #{status}"}

          {:error, reason} ->
            Logger.error("Failed to call HubSpot API: #{inspect(reason)}")
            {:error, "Network error: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Create a new deal in HubSpot.

  ## Parameters
  - user: User struct with HubSpot OAuth tokens
  - deal_data: Map containing deal details

  ## Returns
  - {:ok, deal} on success
  - {:error, reason} on failure
  """
  def create_deal(user, deal_data) do
    Logger.info("Creating HubSpot deal for user #{user.id}")

    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@base_url}/crm/v3/objects/deals"

        headers = [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]

        case Req.post(url, headers: headers, json: deal_data) do
          {:ok, %{status: 201, body: deal}} ->
            Logger.info("Successfully created HubSpot deal: #{deal["id"]}")
            {:ok, deal}

          {:ok, %{status: status, body: body}} ->
            Logger.error("HubSpot API error: #{status} - #{inspect(body)}")
            {:error, "HubSpot API error: #{status}"}

          {:error, reason} ->
            Logger.error("Failed to call HubSpot API: #{inspect(reason)}")
            {:error, "Network error: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Create an engagement (note, call, meeting, etc.) in HubSpot.

  ## Parameters
  - user: User struct with HubSpot OAuth tokens
  - engagement_data: Map containing engagement details

  ## Returns
  - {:ok, engagement} on success
  - {:error, reason} on failure
  """
  def create_engagement(user, engagement_data) do
    Logger.info("Creating HubSpot engagement for user #{user.id}")

    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@base_url}/engagements/v1/engagements"

        headers = [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]

        case Req.post(url, headers: headers, json: engagement_data) do
          {:ok, %{status: 200, body: engagement}} ->
            Logger.info(
              "Successfully created HubSpot engagement: #{engagement["engagement"]["id"]}"
            )

            {:ok, engagement}

          {:ok, %{status: status, body: body}} ->
            Logger.error("HubSpot API error: #{status} - #{inspect(body)}")
            {:error, "HubSpot API error: #{status}"}

          {:error, reason} ->
            Logger.error("Failed to call HubSpot API: #{inspect(reason)}")
            {:error, "Network error: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Associate a deal with a contact in HubSpot.

  ## Parameters
  - user: User struct with HubSpot OAuth tokens
  - deal_id: HubSpot deal ID
  - contact_id: HubSpot contact ID

  ## Returns
  - {:ok, association} on success
  - {:error, reason} on failure
  """
  def associate_deal_with_contact(user, deal_id, contact_id) do
    Logger.info(
      "Associating HubSpot deal #{deal_id} with contact #{contact_id} for user #{user.id}"
    )

    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@base_url}/crm/v3/objects/deals/#{deal_id}/associations/contacts/#{contact_id}/3"

        headers = [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]

        case Req.put(url, headers: headers, json: %{}) do
          {:ok, %{status: 200, body: association}} ->
            Logger.info("Successfully associated deal with contact")
            {:ok, association}

          {:ok, %{status: 204}} ->
            Logger.info("Successfully associated deal with contact")
            {:ok, :associated}

          {:ok, %{status: status, body: body}} ->
            Logger.error("HubSpot API error: #{status} - #{inspect(body)}")
            {:error, "HubSpot API error: #{status}"}

          {:error, reason} ->
            Logger.error("Failed to call HubSpot API: #{inspect(reason)}")
            {:error, "Network error: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

  defp get_access_token(user) do
    case user.hubspot_tokens do
      %{"access_token" => access_token} when is_binary(access_token) ->
        # TODO: Check if token is expired and refresh if needed
        {:ok, access_token}

      _ ->
        Logger.error("No valid HubSpot access token found for user #{user.id}")
        {:error, "HubSpot access not authorized"}
    end
  end
end
