defmodule AiAgent.LLM.Tools.HubSpotTool do
  @moduledoc """
  HubSpot CRM integration tool for managing contacts, notes, and deals.

  This tool allows the AI to:
  - Create and update contacts
  - Add notes to contacts
  - Create and manage deals
  - Search for contacts and companies
  - Update contact properties

  Uses HubSpot API with OAuth2 authentication.
  """

  require Logger

  alias AiAgent.HubSpot.API
  alias AiAgent.User

  @doc """
  Get the OpenAI function calling schema for HubSpot operations.

  Returns the function definitions that OpenAI can use to call HubSpot actions.
  """
  def get_tool_schema do
    [
      %{
        type: "function",
        function: %{
          name: "hubspot_create_contact",
          description: "Create a new contact in HubSpot CRM",
          parameters: %{
            type: "object",
            properties: %{
              email: %{
                type: "string",
                description: "Contact's email address"
              },
              first_name: %{
                type: "string",
                description: "Contact's first name"
              },
              last_name: %{
                type: "string",
                description: "Contact's last name"
              },
              company: %{
                type: "string",
                description: "Contact's company name (optional)"
              },
              phone: %{
                type: "string",
                description: "Contact's phone number (optional)"
              },
              job_title: %{
                type: "string",
                description: "Contact's job title (optional)"
              },
              notes: %{
                type: "string",
                description: "Initial notes about the contact (optional)"
              }
            },
            required: ["email", "first_name", "last_name"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "hubspot_update_contact",
          description: "Update an existing contact in HubSpot CRM",
          parameters: %{
            type: "object",
            properties: %{
              contact_id: %{
                type: "string",
                description: "HubSpot contact ID to update"
              },
              email: %{
                type: "string",
                description: "Contact's email address (alternative identifier)"
              },
              properties: %{
                type: "object",
                description:
                  "Contact properties to update (e.g., {\"phone\": \"+1234567890\", \"jobtitle\": \"CEO\"})"
              }
            },
            required: ["properties"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "hubspot_add_note",
          description: "Add a note to a contact in HubSpot CRM",
          parameters: %{
            type: "object",
            properties: %{
              contact_id: %{
                type: "string",
                description: "HubSpot contact ID"
              },
              email: %{
                type: "string",
                description: "Contact's email address (alternative identifier)"
              },
              note_body: %{
                type: "string",
                description: "Content of the note to add"
              },
              note_type: %{
                type: "string",
                enum: ["MEETING", "CALL", "EMAIL", "TASK", "NOTE"],
                description: "Type of note (defaults to 'NOTE')"
              }
            },
            required: ["note_body"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "hubspot_search_contacts",
          description: "Search for contacts in HubSpot CRM",
          parameters: %{
            type: "object",
            properties: %{
              query: %{
                type: "string",
                description: "Search query (name, email, company, etc.)"
              },
              limit: %{
                type: "integer",
                description: "Maximum number of results to return (defaults to 10)"
              },
              properties: %{
                type: "array",
                items: %{type: "string"},
                description: "Contact properties to include in results (optional)"
              }
            },
            required: ["query"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "hubspot_create_deal",
          description: "Create a new deal in HubSpot CRM",
          parameters: %{
            type: "object",
            properties: %{
              deal_name: %{
                type: "string",
                description: "Name of the deal"
              },
              amount: %{
                type: "number",
                description: "Deal amount in dollars"
              },
              deal_stage: %{
                type: "string",
                description:
                  "Deal stage (e.g., 'appointmentscheduled', 'qualifiedtobuy', 'presentationscheduled')"
              },
              contact_email: %{
                type: "string",
                description: "Email of the contact to associate with this deal (optional)"
              },
              close_date: %{
                type: "string",
                description: "Expected close date in YYYY-MM-DD format (optional)"
              },
              description: %{
                type: "string",
                description: "Deal description or notes (optional)"
              }
            },
            required: ["deal_name", "amount"]
          }
        }
      }
    ]
  end

  @doc """
  Execute a HubSpot tool function.

  ## Parameters
  - user: User struct with HubSpot OAuth tokens
  - function_name: Name of the function to execute
  - arguments: Map of arguments for the function

  ## Returns
  - {:ok, result} on success
  - {:error, reason} on failure
  """
  def execute(user, function_name, arguments) do
    Logger.info("Executing HubSpot function: #{function_name}")

    case function_name do
      "hubspot_create_contact" ->
        create_contact(user, arguments)

      "hubspot_update_contact" ->
        update_contact(user, arguments)

      "hubspot_add_note" ->
        add_note(user, arguments)

      "hubspot_search_contacts" ->
        search_contacts(user, arguments)

      "hubspot_create_deal" ->
        create_deal(user, arguments)

      _ ->
        Logger.error("Unknown HubSpot function: #{function_name}")
        {:error, "Unknown HubSpot function: #{function_name}"}
    end
  end

  # Private functions for each HubSpot action

  defp create_contact(user, args) do
    Logger.info("Creating HubSpot contact for user #{user.id}")

    with {:ok, email} <- get_required_arg(args, "email"),
         {:ok, first_name} <- get_required_arg(args, "first_name"),
         {:ok, last_name} <- get_required_arg(args, "last_name") do
      # Build contact properties
      properties = %{
        "email" => email,
        "firstname" => first_name,
        "lastname" => last_name
      }

      # Add optional properties
      properties =
        properties
        |> maybe_add_property(args, "company")
        |> maybe_add_property(args, "phone")
        |> maybe_add_property(args, "job_title", "jobtitle")

      contact_data = %{
        properties: properties
      }

      case API.create_contact(user, contact_data) do
        {:ok, contact} ->
          Logger.info("Successfully created HubSpot contact: #{contact["id"]}")

          # Add initial note if provided
          result = %{
            contact_id: contact["id"],
            email: email,
            name: "#{first_name} #{last_name}",
            hubspot_url: build_contact_url(contact["id"]),
            message: "Contact '#{first_name} #{last_name}' created successfully in HubSpot"
          }

          # If notes were provided, add them
          case Map.get(args, "notes") do
            nil ->
              {:ok, result}

            notes ->
              case add_note_to_contact(user, contact["id"], notes, "NOTE") do
                {:ok, _} ->
                  {:ok, Map.put(result, :message, result.message <> " with initial notes")}

                {:error, _} ->
                  {:ok, Map.put(result, :message, result.message <> " (note creation failed)")}
              end
          end

        {:error, reason} ->
          Logger.error("Failed to create HubSpot contact: #{inspect(reason)}")
          {:error, "Failed to create HubSpot contact: #{reason}"}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_contact(user, args) do
    Logger.info("Updating HubSpot contact for user #{user.id}")

    with {:ok, properties} <- get_required_arg(args, "properties") do
      # Determine contact identifier
      contact_identifier =
        cond do
          Map.has_key?(args, "contact_id") -> {:id, args["contact_id"]}
          Map.has_key?(args, "email") -> {:email, args["email"]}
          true -> {:error, "Must provide either contact_id or email"}
        end

      case contact_identifier do
        {:error, reason} ->
          {:error, reason}

        {id_type, id_value} ->
          update_data = %{
            properties: properties
          }

          api_function =
            case id_type do
              :id -> &API.update_contact_by_id/3
              :email -> &API.update_contact_by_email/3
            end

          case api_function.(user, id_value, update_data) do
            {:ok, contact} ->
              Logger.info("Successfully updated HubSpot contact: #{contact["id"]}")

              {:ok,
               %{
                 contact_id: contact["id"],
                 properties_updated: Map.keys(properties),
                 hubspot_url: build_contact_url(contact["id"]),
                 message: "Contact updated successfully in HubSpot"
               }}

            {:error, reason} ->
              Logger.error("Failed to update HubSpot contact: #{inspect(reason)}")
              {:error, "Failed to update HubSpot contact: #{reason}"}
          end
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp add_note(user, args) do
    Logger.info("Adding note to HubSpot contact for user #{user.id}")

    with {:ok, note_body} <- get_required_arg(args, "note_body") do
      note_type = Map.get(args, "note_type", "NOTE")

      # Determine contact identifier
      contact_identifier =
        cond do
          Map.has_key?(args, "contact_id") -> {:id, args["contact_id"]}
          Map.has_key?(args, "email") -> {:email, args["email"]}
          true -> {:error, "Must provide either contact_id or email"}
        end

      case contact_identifier do
        {:error, reason} ->
          {:error, reason}

        {id_type, id_value} ->
          # First, get the contact ID if we only have email
          case get_contact_id(user, id_type, id_value) do
            {:ok, contact_id} ->
              add_note_to_contact(user, contact_id, note_body, note_type)

            {:error, reason} ->
              {:error, reason}
          end
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp search_contacts(user, args) do
    Logger.info("Searching HubSpot contacts for user #{user.id}")

    with {:ok, query} <- get_required_arg(args, "query") do
      limit = Map.get(args, "limit", 10)

      properties =
        Map.get(args, "properties", ["email", "firstname", "lastname", "company", "jobtitle"])

      search_data = %{
        query: query,
        limit: limit,
        properties: properties
      }

      case API.search_contacts(user, search_data) do
        {:ok, results} ->
          Logger.info("Found #{length(results)} HubSpot contacts")

          formatted_contacts =
            Enum.map(results, fn contact ->
              %{
                id: contact["id"],
                email: get_property(contact, "email"),
                name:
                  "#{get_property(contact, "firstname")} #{get_property(contact, "lastname")}",
                company: get_property(contact, "company"),
                job_title: get_property(contact, "jobtitle"),
                hubspot_url: build_contact_url(contact["id"])
              }
            end)

          {:ok,
           %{
             contacts: formatted_contacts,
             count: length(formatted_contacts),
             message: "Found #{length(formatted_contacts)} contacts matching '#{query}'"
           }}

        {:error, reason} ->
          Logger.error("Failed to search HubSpot contacts: #{inspect(reason)}")
          {:error, "Failed to search HubSpot contacts: #{reason}"}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_deal(user, args) do
    Logger.info("Creating HubSpot deal for user #{user.id}")

    with {:ok, deal_name} <- get_required_arg(args, "deal_name"),
         {:ok, amount} <- get_required_arg(args, "amount") do
      # Build deal properties
      properties = %{
        "dealname" => deal_name,
        "amount" => amount
      }

      # Add optional properties
      properties =
        properties
        |> maybe_add_property(args, "deal_stage", "dealstage")
        |> maybe_add_property(args, "close_date", "closedate")
        |> maybe_add_property(args, "description")

      deal_data = %{
        properties: properties
      }

      case API.create_deal(user, deal_data) do
        {:ok, deal} ->
          Logger.info("Successfully created HubSpot deal: #{deal["id"]}")

          result = %{
            deal_id: deal["id"],
            deal_name: deal_name,
            amount: amount,
            hubspot_url: build_deal_url(deal["id"]),
            message: "Deal '#{deal_name}' created successfully in HubSpot"
          }

          # Associate with contact if email provided
          case Map.get(args, "contact_email") do
            nil ->
              {:ok, result}

            email ->
              case associate_deal_with_contact(user, deal["id"], email) do
                {:ok, _} ->
                  {:ok,
                   Map.put(result, :message, result.message <> " and associated with contact")}

                {:error, _} ->
                  {:ok,
                   Map.put(result, :message, result.message <> " (contact association failed)")}
              end
          end

        {:error, reason} ->
          Logger.error("Failed to create HubSpot deal: #{inspect(reason)}")
          {:error, "Failed to create HubSpot deal: #{reason}"}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper functions

  defp get_required_arg(args, key) do
    case Map.get(args, key) do
      nil -> {:error, "Missing required argument: #{key}"}
      value -> {:ok, value}
    end
  end

  defp maybe_add_property(properties, args, key, hubspot_key \\ nil) do
    hubspot_key = hubspot_key || key

    case Map.get(args, key) do
      nil -> properties
      value -> Map.put(properties, hubspot_key, value)
    end
  end

  defp get_contact_id(user, :id, contact_id), do: {:ok, contact_id}

  defp get_contact_id(user, :email, email) do
    case API.get_contact_by_email(user, email) do
      {:ok, contact} -> {:ok, contact["id"]}
      {:error, reason} -> {:error, "Failed to find contact by email: #{reason}"}
    end
  end

  defp add_note_to_contact(user, contact_id, note_body, note_type) do
    note_data = %{
      engagement: %{
        type: "NOTE",
        timestamp: System.os_time(:millisecond)
      },
      associations: %{
        contactIds: [contact_id]
      },
      metadata: %{
        body: note_body
      }
    }

    case API.create_engagement(user, note_data) do
      {:ok, engagement} ->
        Logger.info("Successfully added note to HubSpot contact: #{contact_id}")

        {:ok,
         %{
           engagement_id: engagement["engagement"]["id"],
           contact_id: contact_id,
           note_body: note_body,
           message: "Note added successfully to contact"
         }}

      {:error, reason} ->
        Logger.error("Failed to add note to HubSpot contact: #{inspect(reason)}")
        {:error, "Failed to add note: #{reason}"}
    end
  end

  defp associate_deal_with_contact(user, deal_id, contact_email) do
    case API.get_contact_by_email(user, contact_email) do
      {:ok, contact} ->
        case API.associate_deal_with_contact(user, deal_id, contact["id"]) do
          {:ok, _} -> {:ok, :associated}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, "Failed to find contact: #{reason}"}
    end
  end

  defp get_property(contact, property_name) do
    contact
    |> get_in(["properties", property_name, "value"])
    |> case do
      nil -> ""
      value -> value
    end
  end

  defp build_contact_url(contact_id) do
    "https://app.hubspot.com/contacts/#{contact_id}"
  end

  defp build_deal_url(deal_id) do
    "https://app.hubspot.com/deals/#{deal_id}"
  end

  @doc """
  Test HubSpot connection for the dashboard.
  """
  def test_connection(user) do
    case get_access_token(user) do
      {:ok, access_token} ->
        test_token(access_token)
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_access_token(user) do
    case user.hubspot_tokens do
      %{"access_token" => access_token} when is_binary(access_token) ->
        {:ok, access_token}

      _ ->
        Logger.error("No valid HubSpot access token found for user #{user.id}")
        {:error, "HubSpot access not authorized"}
    end
  end

  @doc """
  Test if a HubSpot access token is valid by making a simple API call.
  """
  def test_token(access_token) do
    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Accept", "application/json"}
    ]

    case Req.get("https://api.hubapi.com/crm/v3/owners", headers: headers) do
      {:ok, %{status: 200}} ->
        {:ok, :valid}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
