defmodule AiAgent.LLM.ToolCalling do
  @moduledoc """
  Tool calling system for executing user actions through OpenAI function calling.

  This module enables the AI to perform actions on behalf of the user such as:
  - Scheduling appointments in Google Calendar
  - Sending emails through Gmail
  - Adding notes and contacts in HubSpot CRM
  - Managing tasks and reminders

  Uses OpenAI's function calling feature to determine when and how to use tools.
  """

  require Logger

  alias AiAgent.LLM.Tools.CalendarTool
  alias AiAgent.LLM.Tools.EmailTool
  alias AiAgent.LLM.Tools.HubSpotTool
  alias AiAgent.User

  @openai_chat_url "https://api.openai.com/v1/chat/completions"
  @default_model "gpt-4o"
  @default_max_tokens 1000

  @doc """
  Enhanced RAG query with tool calling capabilities.

  This function extends the basic RAG system to include tool execution when the AI
  determines that an action needs to be performed.

  ## Parameters
  - user: User struct
  - question: User's query/request
  - opts: Options map with keys:
    - :enable_tools - Whether to enable tool calling (default: true)
    - :model - OpenAI model to use
    - :max_tokens - Maximum response tokens
    - :context_limit - Number of context documents to retrieve
    - :similarity_threshold - Similarity threshold for context retrieval

  ## Returns
  - {:ok, %{response: string, tools_used: [actions], context_used: [docs]}} on success
  - {:error, reason} on failure

  ## Examples
      # Simple question (no tools needed)
      iex> AiAgent.LLM.ToolCalling.ask_with_tools(user, "Who mentioned baseball?")
      {:ok, %{response: "John mentioned...", tools_used: [], context_used: [...]}}
      
      # Action request (tools will be used)
      iex> AiAgent.LLM.ToolCalling.ask_with_tools(user, "Schedule a meeting with John tomorrow at 2pm")
      {:ok, %{response: "I've scheduled...", tools_used: [%{tool: "calendar", action: "create_event"}], context_used: [...]}}
  """
  def ask_with_tools(user, question, opts \\ %{}) when is_binary(question) do
    Logger.info("Tool-enabled query from user #{user.id}: #{String.slice(question, 0, 100)}...")

    enable_tools = Map.get(opts, :enable_tools, true)
    model = Map.get(opts, :model, @default_model)
    max_tokens = Map.get(opts, :max_tokens, @default_max_tokens)
    context_limit = Map.get(opts, :context_limit, 5)
    similarity_threshold = Map.get(opts, :similarity_threshold, 0.3)

    with {:ok, context_docs} <-
           get_relevant_context(user, question, context_limit, similarity_threshold),
         {:ok, result} <-
           process_with_tools(user, question, context_docs, enable_tools, model, max_tokens) do
      Logger.info(
        "Tool-enabled query completed. Used #{length(result.tools_used)} tools, #{length(result.context_used)} context docs."
      )

      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("Tool-enabled query failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get available tools schema for OpenAI function calling.

  Returns the function definitions that OpenAI can call.
  """
  def get_available_tools do
    [
      CalendarTool.get_tool_schema(),
      EmailTool.get_tool_schema(),
      HubSpotTool.get_tool_schema()
    ]
    |> List.flatten()
  end

  @doc """
  Execute a specific tool action.

  ## Parameters
  - user: User struct
  - tool_name: Name of the tool to execute
  - function_name: Specific function within the tool
  - arguments: Arguments for the function call

  ## Returns
  - {:ok, result} on success
  - {:error, reason} on failure
  """
  def execute_tool(user, tool_name, function_name, arguments) do
    Logger.info("Executing tool: #{tool_name}.#{function_name} for user #{user.id}")

    case tool_name do
      "calendar" ->
        CalendarTool.execute(user, function_name, arguments)

      "email" ->
        EmailTool.execute(user, function_name, arguments)

      "hubspot" ->
        HubSpotTool.execute(user, function_name, arguments)

      _ ->
        Logger.error("Unknown tool: #{tool_name}")
        {:error, "Unknown tool: #{tool_name}"}
    end
  end

  # Private functions

  defp get_relevant_context(user, question, limit, threshold) do
    # Use the existing RAG context retrieval
    case AiAgent.LLM.RAGQuery.retrieve_relevant_context(user, question, limit, threshold) do
      {:ok, docs} ->
        {:ok, docs}

      {:error, reason} ->
        Logger.warn("Failed to retrieve context: #{reason}")
        # Continue without context rather than failing
        {:ok, []}
    end
  end

  defp process_with_tools(user, question, context_docs, enable_tools, model, max_tokens) do
    # Build the context from documents
    context = build_document_context(context_docs)

    # Create the enhanced system prompt with tool awareness
    system_prompt = build_tool_aware_system_prompt()

    # Build user prompt with context
    user_prompt = build_user_prompt_with_context(question, context)

    # Prepare messages
    messages = [
      %{role: "system", content: system_prompt},
      %{role: "user", content: user_prompt}
    ]

    # Get available tools if enabled
    tools = if enable_tools, do: get_available_tools(), else: []

    # Call OpenAI with function calling
    case call_openai_with_tools(messages, tools, model, max_tokens) do
      {:ok, %{response: response, tool_calls: tool_calls}} ->
        # Execute any tool calls
        case execute_tool_calls(user, tool_calls) do
          {:ok, tool_results} ->
            # If tools were called, we might need a follow-up call to get the final response
            final_response =
              if Enum.empty?(tool_calls) do
                response
              else
                get_final_response_after_tools(
                  user,
                  question,
                  context,
                  response,
                  tool_results,
                  model,
                  max_tokens
                )
              end

            {:ok,
             %{
               response: final_response,
               tools_used: tool_results,
               context_used: context_docs,
               metadata: %{
                 model_used: model,
                 tools_enabled: enable_tools,
                 tool_calls_made: length(tool_calls)
               }
             }}

          {:error, reason} ->
            {:error, "Tool execution failed: #{reason}"}
        end

      {:error, reason} ->
        {:error, "OpenAI API call failed: #{reason}"}
    end
  end

  defp build_document_context(documents) when is_list(documents) do
    if Enum.empty?(documents) do
      "No relevant documents found."
    else
      documents
      |> Enum.with_index(1)
      |> Enum.map(fn {doc, index} ->
        """
        Document #{index} (#{doc.type} from #{doc.source}, similarity: #{Float.round(doc.similarity, 3)}):
        #{doc.content}
        """
      end)
      |> Enum.join("\n---\n")
    end
  end

  defp build_tool_aware_system_prompt do
    """
    You are an AI assistant for a financial advisor with access to their client information and the ability to perform actions on their behalf.

    You have access to these tools:
    1. Google Calendar - Schedule, modify, or cancel appointments
    2. Gmail - Send emails to clients or contacts
    3. HubSpot CRM - Add notes, create contacts, update client information

    Your role is to:
    1. Answer questions about clients based on the provided context documents
    2. When the user requests an action (like "schedule a meeting" or "send an email"), use the appropriate tools
    3. Provide clear, helpful responses that confirm what actions were taken
    4. Maintain professional tone appropriate for a financial advisor's assistant

    Guidelines for tool usage:
    - Only use tools when the user explicitly requests an action
    - Always confirm the action before executing (unless user specifically says to proceed)
    - If you need more information to complete an action, ask for clarification
    - When scheduling meetings, try to find contact information from the provided context
    - When sending emails, use professional language appropriate for financial services

    Guidelines for responses:
    - Be concise but thorough
    - Base answers on the provided context documents when available
    - If you used tools, briefly describe what was accomplished
    - If tools failed, explain what went wrong and suggest alternatives
    """
  end

  defp build_user_prompt_with_context(question, context) do
    """
    CONTEXT DOCUMENTS:
    #{context}

    USER REQUEST: #{question}

    Please help the user with their request. If they're asking for information, use the context documents to provide an accurate answer. If they're requesting an action (like scheduling, emailing, or updating CRM), use the appropriate tools to complete the task.
    """
  end

  defp call_openai_with_tools(messages, tools, model, max_tokens) do
    case get_openai_key() do
      nil ->
        {:error, "OpenAI API key not configured"}

      api_key ->
        headers = [
          {"Authorization", "Bearer #{api_key}"},
          {"Content-Type", "application/json"}
        ]

        payload = %{
          model: model,
          messages: messages,
          max_tokens: max_tokens,
          temperature: 0.7
        }

        # Add tools if available
        payload =
          if Enum.empty?(tools) do
            payload
          else
            payload
            |> Map.put(:tools, tools)
            |> Map.put(:tool_choice, "auto")
          end

        Logger.debug("Calling OpenAI with #{length(tools)} tools available")

        case Req.post(@openai_chat_url, headers: headers, json: payload) do
          {:ok, %{status: 200, body: %{"choices" => [choice | _]}}} ->
            message = choice["message"]
            response = Map.get(message, "content", "")
            tool_calls = Map.get(message, "tool_calls", [])

            {:ok, %{response: response, tool_calls: tool_calls}}

          {:ok, %{status: status, body: body}} ->
            Logger.error("OpenAI API error: #{status} - #{inspect(body)}")
            {:error, "OpenAI API error: #{status}"}

          {:error, reason} ->
            Logger.error("Failed to call OpenAI API: #{inspect(reason)}")
            {:error, "Network error: #{inspect(reason)}"}
        end
    end
  end

  defp execute_tool_calls(user, tool_calls) do
    if Enum.empty?(tool_calls) do
      {:ok, []}
    else
      results =
        Enum.map(tool_calls, fn tool_call ->
          function = tool_call["function"]
          tool_name = String.split(function["name"], "_") |> hd()
          function_name = function["name"]

          # Parse arguments (they come as JSON string)
          arguments =
            case Jason.decode(function["arguments"]) do
              {:ok, args} -> args
              {:error, _} -> %{}
            end

          case execute_tool(user, tool_name, function_name, arguments) do
            {:ok, result} ->
              %{
                tool: tool_name,
                function: function_name,
                arguments: arguments,
                result: result,
                success: true
              }

            {:error, reason} ->
              %{
                tool: tool_name,
                function: function_name,
                arguments: arguments,
                result: reason,
                success: false
              }
          end
        end)

      {:ok, results}
    end
  end

  defp get_final_response_after_tools(
         user,
         original_question,
         context,
         initial_response,
         tool_results,
         model,
         max_tokens
       ) do
    # Build a follow-up prompt that includes the tool execution results
    tool_summary =
      Enum.map(tool_results, fn result ->
        if result.success do
          "✅ #{result.tool}.#{result.function} succeeded: #{inspect(result.result)}"
        else
          "❌ #{result.tool}.#{result.function} failed: #{result.result}"
        end
      end)
      |> Enum.join("\n")

    follow_up_prompt = """
    The user asked: "#{original_question}"

    I executed the following tools:
    #{tool_summary}

    Please provide a final response to the user that summarizes what was accomplished and addresses their original request.
    """

    messages = [
      %{
        role: "system",
        content:
          "You are a helpful assistant. Provide a clear summary of the actions taken and their results."
      },
      %{role: "user", content: follow_up_prompt}
    ]

    case call_openai_with_tools(messages, [], model, max_tokens) do
      {:ok, %{response: final_response}} ->
        final_response

      {:error, _} ->
        # Fallback to a simple summary if the follow-up call fails
        "I completed your request. " <> tool_summary
    end
  end

  defp get_openai_key do
    System.get_env("OPENAI_API_KEY")
  end
end
