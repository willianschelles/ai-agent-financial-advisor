defmodule AiAgent.LLM.Tools.EmailTool do
  @moduledoc """
  Gmail integration tool for sending and managing emails.

  This tool allows the AI to:
  - Send emails to clients and contacts
  - Reply to emails
  - Search for email addresses in the context
  - Draft professional emails for financial services

  Uses Gmail API with OAuth2 authentication.
  """

  require Logger

  alias AiAgent.Google.GmailAPI
  alias AiAgent.User

  @doc """
  Get the OpenAI function calling schema for email operations.

  Returns the function definitions that OpenAI can use to call email actions.
  """
  def get_tool_schema do
    [
      %{
        type: "function",
        function: %{
          name: "email_send",
          description: "Send an email to one or more recipients",
          parameters: %{
            type: "object",
            properties: %{
              to: %{
                type: "array",
                items: %{type: "string"},
                description: "List of recipient email addresses"
              },
              subject: %{
                type: "string",
                description: "Email subject line"
              },
              body: %{
                type: "string",
                description: "Email body content"
              },
              cc: %{
                type: "array",
                items: %{type: "string"},
                description: "List of CC email addresses (optional)"
              },
              bcc: %{
                type: "array",
                items: %{type: "string"},
                description: "List of BCC email addresses (optional)"
              },
              reply_to: %{
                type: "string",
                description: "Message ID to reply to (optional)"
              }
            },
            required: ["to", "subject", "body"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "email_draft",
          description: "Create a professional email draft for review before sending",
          parameters: %{
            type: "object",
            properties: %{
              recipient_name: %{
                type: "string",
                description: "Name of the primary recipient"
              },
              purpose: %{
                type: "string",
                description:
                  "Purpose of the email (e.g., 'follow up on meeting', 'send portfolio update', 'schedule appointment')"
              },
              key_points: %{
                type: "array",
                items: %{type: "string"},
                description: "Key points to include in the email"
              },
              tone: %{
                type: "string",
                enum: ["professional", "friendly", "formal", "urgent"],
                description: "Tone of the email (defaults to 'professional')"
              },
              call_to_action: %{
                type: "string",
                description: "What you want the recipient to do (optional)"
              }
            },
            required: ["recipient_name", "purpose", "key_points"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "email_find_contact",
          description: "Find email addresses for a person or company from the context documents",
          parameters: %{
            type: "object",
            properties: %{
              name: %{
                type: "string",
                description: "Name of the person or company to find email for"
              },
              context_hint: %{
                type: "string",
                description: "Additional context to help find the right contact (optional)"
              }
            },
            required: ["name"]
          }
        }
      }
    ]
  end

  @doc """
  Execute an email tool function.

  ## Parameters
  - user: User struct with Google OAuth tokens
  - function_name: Name of the function to execute
  - arguments: Map of arguments for the function

  ## Returns
  - {:ok, result} on success
  - {:error, reason} on failure
  """
  def execute(user, function_name, arguments) do
    Logger.info("Executing email function: #{function_name}")

    case function_name do
      "email_send" ->
        send_email(user, arguments)

      "email_draft" ->
        draft_email(user, arguments)

      "email_find_contact" ->
        find_contact(user, arguments)

      _ ->
        Logger.error("Unknown email function: #{function_name}")
        {:error, "Unknown email function: #{function_name}"}
    end
  end

  # Private functions for each email action

  defp send_email(user, args) do
    Logger.info("Sending email for user #{user.id}")

    # Validate required arguments
    with {:ok, to_addresses} <- get_required_arg(args, "to"),
         {:ok, subject} <- get_required_arg(args, "subject"),
         {:ok, body} <- get_required_arg(args, "body") do
      # Build email data
      email_data = %{
        to: to_addresses,
        subject: subject,
        body: body,
        cc: Map.get(args, "cc", []),
        bcc: Map.get(args, "bcc", []),
        reply_to: Map.get(args, "reply_to")
      }

      # Call Gmail API
      case GmailAPI.send_email(user, email_data) do
        {:ok, message} ->
          Logger.info("Successfully sent email: #{message["id"]}")

          {:ok,
           %{
             message_id: message["id"],
             to: to_addresses,
             subject: subject,
             thread_id: message["threadId"],
             message: "Email sent successfully to #{Enum.join(to_addresses, ", ")}"
           }}

        {:error, reason} ->
          Logger.error("Failed to send email: #{inspect(reason)}")
          {:error, "Failed to send email: #{reason}"}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp draft_email(user, args) do
    Logger.info("Drafting email for user #{user.id}")

    with {:ok, recipient_name} <- get_required_arg(args, "recipient_name"),
         {:ok, purpose} <- get_required_arg(args, "purpose"),
         {:ok, key_points} <- get_required_arg(args, "key_points") do
      tone = Map.get(args, "tone", "professional")
      call_to_action = Map.get(args, "call_to_action")

      # Generate professional email content
      draft = generate_email_draft(recipient_name, purpose, key_points, tone, call_to_action)

      {:ok,
       %{
         draft: draft,
         recipient_name: recipient_name,
         purpose: purpose,
         message:
           "Email draft created for #{recipient_name}. Review and use email_send to send it."
       }}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_contact(user, args) do
    Logger.info("Finding contact information for user #{user.id}")

    with {:ok, name} <- get_required_arg(args, "name") do
      context_hint = Map.get(args, "context_hint", "")

      Logger.debug("Searching for contact: '#{name}' with context: '#{context_hint}'")

      # Try multiple search strategies
      emails = find_email_with_multiple_strategies(user, name, context_hint)

      if Enum.empty?(emails) do
        Logger.warning("No emails found for '#{name}', trying fallback strategies")
        
        # Try additional fallback strategies
        fallback_emails = try_fallback_email_search(user, name)
        
        if Enum.empty?(fallback_emails) do
          # Final attempt: Try HubSpot search
          Logger.info("Attempting HubSpot contact search for '#{name}'")
          hubspot_emails = try_hubspot_contact_search(user, name)
          
          if Enum.empty?(hubspot_emails) do
            {:ok,
             %{
               emails_found: [],
               message: "No email addresses found for '#{name}' in documents or HubSpot"
             }}
          else
            {:ok,
             %{
               emails_found: hubspot_emails,
               message: "Found #{length(hubspot_emails)} email address(es) for '#{name}' from HubSpot"
             }}
          end
        else
          {:ok,
           %{
             emails_found: fallback_emails,
             message: "Found #{length(fallback_emails)} email address(es) for '#{name}' using fallback search"
           }}
        end
      else
        {:ok,
         %{
           emails_found: emails,
           message: "Found #{length(emails)} email address(es) for '#{name}'"
         }}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp find_email_with_multiple_strategies(user, name, context_hint) do
    strategies = [
      # Strategy 1: Search with full name and context
      fn -> search_documents_for_email(user, "#{name} #{context_hint}", name, 0.2) end,
      
      # Strategy 2: Search with just the name (lower threshold)
      fn -> search_documents_for_email(user, name, name, 0.15) end,
      
      # Strategy 3: Search with first name only if it's a full name
      fn -> 
        first_name = String.split(name) |> List.first()
        if first_name != name do
          search_documents_for_email(user, first_name, name, 0.1)
        else
          []
        end
      end,
      
      # Strategy 4: Search with last name only if it's a full name
      fn -> 
        parts = String.split(name)
        if length(parts) > 1 do
          last_name = List.last(parts)
          search_documents_for_email(user, last_name, name, 0.1)
        else
          []
        end
      end
    ]
    
    # Try each strategy until we find emails
    Enum.find_value(strategies, [], fn strategy ->
      emails = strategy.()
      if Enum.empty?(emails), do: nil, else: emails
    end) || []
  end
  
  defp search_documents_for_email(user, search_query, original_name, threshold) do
    case AiAgent.Embeddings.VectorStore.find_similar_documents(user, search_query, %{
           limit: 15,
           threshold: threshold
         }) do
      {:ok, documents} ->
        Logger.debug("Found #{length(documents)} documents for query '#{search_query}'")
        extract_emails_from_documents(documents, original_name)
        
      {:error, reason} ->
        Logger.warning("Document search failed for '#{search_query}': #{reason}")
        []
    end
  end
  
  defp try_fallback_email_search(user, name) do
    # Strategy: Search for any mention of the name with very low threshold
    case AiAgent.Embeddings.VectorStore.find_similar_documents(user, name, %{
           limit: 20,
           threshold: 0.05
         }) do
      {:ok, documents} ->
        Logger.debug("Fallback search found #{length(documents)} documents")
        
        # Extract ALL emails from these documents and try to match them intelligently
        all_emails = documents
        |> Enum.flat_map(fn doc ->
          Regex.scan(~r/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/, doc.content)
          |> List.flatten()
        end)
        |> Enum.uniq()
        
        Logger.debug("Found #{length(all_emails)} unique emails in fallback search")
        
        # Try to match emails to the name
        name_parts = String.split(String.downcase(name), " ")
        
        matched_emails = Enum.filter(all_emails, fn email ->
          email_lower = String.downcase(email)
          Enum.any?(name_parts, fn part ->
            String.contains?(email_lower, part) and String.length(part) > 2
          end)
        end)
        
        Enum.map(matched_emails, fn email ->
          %{
            email: email,
            source: "fallback_search",
            confidence: "low"
          }
        end)
        
      {:error, _} ->
        []
    end
  end
  
  defp try_hubspot_contact_search(user, name) do
    # Try to find the contact in HubSpot
    case AiAgent.LLM.Tools.HubSpotTool.execute(user, "hubspot_search_contacts", %{
           "query" => name,
           "limit" => 5
         }) do
      {:ok, result} ->
        Logger.debug("HubSpot search result: #{inspect(result)}")
        
        case result do
          %{"contacts" => contacts} when is_list(contacts) ->
            # Extract emails from HubSpot contacts
            Enum.flat_map(contacts, fn contact ->
              case contact do
                %{"properties" => %{"email" => email}} when is_binary(email) ->
                  [%{
                    email: email,
                    source: "hubspot",
                    confidence: "high"
                  }]
                _ -> []
              end
            end)
            
          _ -> []
        end
        
      {:error, reason} ->
        Logger.debug("HubSpot contact search failed: #{reason}")
        []
    end
  end

  # Helper functions

  defp get_required_arg(args, key) do
    case Map.get(args, key) do
      nil -> {:error, "Missing required argument: #{key}"}
      value -> {:ok, value}
    end
  end

  defp generate_email_draft(recipient_name, purpose, key_points, tone, call_to_action) do
    # Build greeting based on tone
    greeting =
      case tone do
        "formal" -> "Dear #{recipient_name},"
        "friendly" -> "Hi #{recipient_name},"
        _ -> "Hello #{recipient_name},"
      end

    # Build opening line based on purpose
    opening =
      case purpose do
        "follow up on meeting" ->
          "I wanted to follow up on our recent meeting."

        "send portfolio update" ->
          "I'm writing to provide you with an update on your portfolio."

        "schedule appointment" ->
          "I hope this email finds you well. I'd like to schedule a time to meet with you."

        _ ->
          "I hope this email finds you well."
      end

    # Format key points
    points_text =
      key_points
      |> Enum.map(fn point -> "• #{point}" end)
      |> Enum.join("\n")

    # Build closing based on call to action
    closing =
      if call_to_action do
        "#{call_to_action}\n\nPlease let me know if you have any questions."
      else
        "Please let me know if you have any questions or would like to discuss this further."
      end

    # Build signature
    signature =
      case tone do
        "formal" -> "Sincerely,\n[Your Name]\n[Your Title]\n[Your Contact Information]"
        "friendly" -> "Best regards,\n[Your Name]"
        _ -> "Best regards,\n[Your Name]\n[Your Title]"
      end

    # Combine all parts
    """
    #{greeting}

    #{opening}

    #{points_text}

    #{closing}

    #{signature}
    """
  end

  defp extract_emails_from_documents(documents, name) do
    email_regex = ~r/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/

    documents
    |> Enum.flat_map(fn doc ->
      # Extract all email addresses from the document content
      Regex.scan(email_regex, doc.content)
      |> List.flatten()
      |> Enum.filter(fn email ->
        # Check if the email is likely associated with the name
        email_matches_name?(email, name, doc.content)
      end)
    end)
    |> Enum.uniq()
    |> Enum.map(fn email ->
      %{
        email: email,
        source: "document_search",
        confidence: "medium"
      }
    end)
  end

  defp email_matches_name?(email, name, content) do
    # Enhanced heuristic: check if the name appears near the email in the content
    name_parts = String.split(String.downcase(name), " ") |> Enum.filter(&(String.length(&1) > 2))
    email_lower = String.downcase(email)
    content_lower = String.downcase(content)

    # Check if any part of the name appears in the email address
    name_in_email =
      Enum.any?(name_parts, fn part ->
        String.contains?(email_lower, part)
      end)

    # Check if the name appears within 200 characters of the email in the content
    email_index = String.split(content_lower, email_lower)

    name_near_email =
      if length(email_index) > 1 do
        # Get text around the email (before and after)
        context_before = email_index |> Enum.at(0) |> String.slice(-100, 100)
        context_after = email_index |> Enum.at(1) |> String.slice(0, 100)
        context = context_before <> " " <> context_after

        Enum.any?(name_parts, fn part ->
          String.contains?(context, part)
        end)
      else
        false
      end

    # Check if the name appears anywhere in the content near common email indicators
    name_near_indicators = 
      if Enum.any?(name_parts, fn part -> String.contains?(content_lower, part) end) do
        # Check if email appears in content with common patterns
        String.contains?(content_lower, ["email:", "contact:", "from:", "to:", "reply-to:"]) or
        String.contains?(content_lower, [" email ", " contact ", " address "])
      else
        false
      end

    name_in_email or name_near_email or name_near_indicators
  end
end
