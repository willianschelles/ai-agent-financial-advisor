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
  alias AiAgent.{User, WorkflowEngine, TaskManager, SimpleWorkflowEngine}

  @openai_chat_url "https://api.openai.com/v1/chat/completions"
  @default_model "gpt-4o"
  @default_max_tokens 1000

  @doc """
  Enhanced RAG query with tool calling and task memory capabilities.

  This function extends the basic RAG system to include tool execution and persistent
  task tracking for multi-step workflows. It can create tasks for complex requests
  that may require waiting for external events.

  ## Parameters
  - user: User struct
  - question: User's query/request
  - opts: Options map with keys:
    - :enable_tools - Whether to enable tool calling (default: true)
    - :enable_workflows - Whether to enable workflow creation (default: true)
    - :model - OpenAI model to use
    - :max_tokens - Maximum response tokens
    - :context_limit - Number of context documents to retrieve
    - :similarity_threshold - Similarity threshold for context retrieval
    - :task_id - ID of existing task to continue (optional)

  ## Returns
  - {:ok, %{response: string, tools_used: [actions], context_used: [docs], task: task}} on success
  - {:error, reason} on failure

  ## Examples
      # Simple question (no tools needed)
      iex> AiAgent.LLM.ToolCalling.ask_with_tools(user, "Who mentioned baseball?")
      {:ok, %{response: "John mentioned...", tools_used: [], context_used: [...]}}

      # Multi-step action (creates workflow)
      iex> AiAgent.LLM.ToolCalling.ask_with_tools(user, "Schedule a meeting with John tomorrow at 2pm and send him a follow-up email")
      {:ok, %{response: "I've started...", tools_used: [...], task: %Task{...}}}
  """
  def ask_with_tools(user, question, opts \\ %{}) when is_binary(question) do
    Logger.info("Tool-enabled query from user #{user.id}: #{String.slice(question, 0, 100)}...")

    enable_tools = Map.get(opts, :enable_tools, true)
    enable_workflows = Map.get(opts, :enable_workflows, true)
    task_id = Map.get(opts, :task_id)

    # Check if this is continuing an existing task
    case task_id do
      nil ->
        # New request - determine if it needs a workflow
        if enable_workflows and is_complex_request?(question) do
          handle_workflow_request(user, question, opts)
        else
          handle_simple_request(user, question, opts)
        end

      task_id when is_integer(task_id) ->
        # Continue existing task
        continue_existing_task(user, task_id, question, opts)
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
        Logger.warning("Failed to retrieve context: #{reason}")
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
    You are an intelligent AI assistant for a financial advisor. You have access to their client information through context documents and can perform actions using various tools.

    Available tools:
    - Gmail: Send professional emails
    - Google Calendar: Schedule and manage appointments
    - HubSpot CRM: Manage client relationships and notes

    Your approach:
    1. **Context-Driven Intelligence**: Always review the provided context documents first. Use specific information from emails, CRM records, and notes to inform your responses and actions. When creating emails with information about topics (like speakers, events, or projects), you MUST include the specific details from the context documents - names, dates, credentials, locations, etc.

    2. **Dynamic Decision Making**: Choose the most appropriate action based on the situation:
       - If user wants to communicate with someone, look for their contact info in context
       - If discussing a topic, incorporate relevant details from your knowledge and context
       - If scheduling, consider existing calendar information and preferences

    3. **Professional Communication**:
       - Create emails that are specific and valuable, not generic
       - CRITICAL: When sending informational emails, include actual details from context documents. For example, if sending information about speakers, include their names, titles, background, and specific details rather than generic statements
       - Use context to personalize communications appropriately
       - Generate clear, professional subject lines that capture the essence of the message

    4. **Intelligent Tool Usage**:
       - Execute actions when requested, but use context to enhance them
       - For search+email requests: First search the context documents thoroughly, then compile the findings into a comprehensive email
       - For dates: 'Tomorrow' means the next calendar day from today (June 23, 2025)
       - Find contact information from context when possible
       - Ask for clarification only when genuinely needed
       - When asked to search and send information, always include specific details found in your search

    5. **Natural Interaction**: Respond conversationally while being helpful. Don't follow rigid patterns - adapt to what makes sense for each specific request.

    Your goal is to be genuinely helpful by combining your knowledge with the specific context about this advisor's clients and business to provide valuable, personalized assistance.
    """
  end

  defp build_user_prompt_with_context(question, context) do
    """
    CONTEXT DOCUMENTS:
    #{context}

    USER REQUEST: #{question}

    Please help the user with their request. If they're asking for information, use the context documents to provide an accurate answer. If they're requesting an action (like scheduling, emailing, or updating CRM), use the appropriate tools to complete the task.

    IMPORTANT: When sending informational emails, you MUST include specific details from the context documents above. For example, if sending information about speakers or events, include actual names, credentials, dates, and other factual information rather than generic statements.
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

  # New workflow and task handling functions

  defp is_complex_request?(question) do
    question_lower = String.downcase(question)

    # Skip analysis prompts and internal system prompts
    analysis_indicators = [
      "analyze this", "provide a json response", "determine the next steps",
      "extract recipient information", "original request:", "completed steps:"
    ]

    is_analysis_prompt = Enum.any?(analysis_indicators, fn indicator ->
      String.contains?(question_lower, indicator)
    end)

    if is_analysis_prompt do
      false
    else
      # Check for common search+email pattern first - handle this as a simple request with tools
      search_and_email_pattern = Regex.match?(~r/search\s+.+\s+and\s+send\s+.+@.+/i, question_lower)
      
      if search_and_email_pattern do
        # This is a search+email request - handle it as simple with tools enabled
        false
      else
        # First check for indicators of complex, multi-step requests
        multi_step_indicators = [
          " and ", " then ", " after ", " following ", " once ", " when ",
          " if ", " unless ", " provided ", " assuming ",
          "schedule.*send", "send.*schedule", "create.*notify", "notify.*create",
          "wait for", "follow up", "remind me", "check back",
          "if.*accepts", "if.*confirms", "if.*agrees", "if.*available"
        ]

        is_complex = Enum.any?(multi_step_indicators, fn indicator ->
          # Check if it's a regex pattern (contains *)
          if String.contains?(indicator, "*") do
            regex_pattern = String.replace(indicator, "*", ".*")
            Regex.match?(~r/#{regex_pattern}/i, question_lower)
          else
            String.contains?(question_lower, indicator)
          end
        end)

        if is_complex do
          # Special case: information gathering + email sending should be simple
          info_email_patterns = [
            ~r/search for .+ (?:info|information) and send to .+/i,
            ~r/gather .+ (?:info|information) .+ and (?:send|email) .+/i,
            ~r/find .+ (?:info|information) .+ and (?:send|email) .+/i,
            ~r/get .+ (?:info|information) .+ and (?:send|email) .+/i
          ]
          
          is_info_email = Enum.any?(info_email_patterns, fn pattern ->
            Regex.match?(pattern, question_lower)
          end)
          
          if is_info_email do
            false  # Treat as simple action, not complex workflow
          else
            true   # Complex requests need workflows
          end
        else
          # Check for action-based requests that require tools/workflows
          action_patterns = [
            ~r/^send (?:an? )?email to .+/i,
            ~r/^email .+ about .+/i,
            ~r/^schedule (?:a )?meeting with .+/i,
            ~r/^create (?:a )?calendar event .+/i,
            ~r/^add .+ to hubspot/i,
            ~r/^send .+ (?:an? )?message/i,
            ~r/^create .+ contact/i,
            ~r/^update .+ in hubspot/i,
            ~r/^cancel .+ meeting/i,
            ~r/^reschedule .+/i,
            ~r/^delete .+/i,
            ~r/^archive .+/i
          ]

          is_action_request = Enum.any?(action_patterns, fn pattern ->
            Regex.match?(pattern, question_lower)
          end)

          # Return true only for action requests, false for informational questions
          is_action_request
        end
      end
    end
  end

  defp handle_workflow_request(user, question, opts) do
    Logger.info("Handling workflow request for user #{user.id}")

    # Try the new simplified email->calendar workflow first
    case SimpleWorkflowEngine.handle_email_calendar_request(user, question) do
      {:ok, result} ->
        # Email->calendar workflow handled successfully
        {:ok, %{
          response: result.message || "Email sent, waiting for reply to create calendar event",
          tools_used: [],
          context_used: [],
          task: nil,
          waiting: true,
          metadata: %{
            workflow_type: "email_calendar",
            workflow_created: true,
            email_data: result[:email_data]
          }
        }}

      {:not_email_calendar_workflow, _request} ->
        # Not an email->calendar workflow, try the original workflow engine
        case WorkflowEngine.create_and_execute_workflow(user, question, opts) do
          {:ok, result} ->
            format_workflow_result(result, true)

          {:waiting, task} ->
            Logger.info("Workflow created task #{task.id} and is waiting for external event")
            {:ok, %{
              response: build_waiting_response(task),
              tools_used: [],
              context_used: [],
              task: task,
              waiting: true,
              metadata: %{
                workflow_created: true,
                task_id: task.id,
                waiting_for: task.waiting_for
              }
            }}

          {:error, reason} ->
            Logger.error("Workflow creation failed: #{reason}")
            # Fallback to simple request handling
            handle_simple_request(user, question, opts)
        end

      {:error, reason} ->
        Logger.error("Simple workflow failed: #{reason}")
        # Fallback to original workflow engine
        case WorkflowEngine.create_and_execute_workflow(user, question, opts) do
          {:ok, result} ->
            format_workflow_result(result, true)

          {:waiting, task} ->
            Logger.info("Workflow created task #{task.id} and is waiting for external event")
            {:ok, %{
              response: build_waiting_response(task),
              tools_used: [],
              context_used: [],
              task: task,
              waiting: true,
              metadata: %{
                workflow_created: true,
                task_id: task.id,
                waiting_for: task.waiting_for
              }
            }}

          {:error, reason} ->
            Logger.error("All workflow methods failed: #{reason}")
            # Final fallback to simple request handling
            handle_simple_request(user, question, opts)
        end
    end
  end

  defp handle_simple_request(user, question, opts) do
    Logger.debug("Handling simple request for user #{user.id}")

    model = Map.get(opts, :model, @default_model)
    max_tokens = Map.get(opts, :max_tokens, @default_max_tokens)
    context_limit = Map.get(opts, :context_limit, 5)
    similarity_threshold = Map.get(opts, :similarity_threshold, 0.3)
    enable_tools = Map.get(opts, :enable_tools, true)

    with {:ok, context_docs} <-
           get_relevant_context(user, question, context_limit, similarity_threshold),
         {:ok, result} <-
           process_with_tools(user, question, context_docs, enable_tools, model, max_tokens) do

      # Add task field for consistency
      enhanced_result = Map.put(result, :task, nil)

      Logger.info(
        "Simple request completed. Used #{length(result.tools_used)} tools, #{length(result.context_used)} context docs."
      )

      {:ok, enhanced_result}
    else
      {:error, reason} ->
        Logger.error("Simple request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp continue_existing_task(user, task_id, question, opts) do
    Logger.info("Continuing existing task #{task_id} for user #{user.id}")

    case TaskManager.get_task(task_id) do
      {:ok, task} ->
        if task.user_id == user.id do
          # Update task with new input and continue workflow
          case WorkflowEngine.execute_workflow(task, user, Map.put(opts, :user_input, question)) do
            {:ok, result} ->
              format_workflow_result(result, false)

            {:waiting, updated_task} ->
              {:ok, %{
                response: build_waiting_response(updated_task),
                tools_used: [],
                context_used: [],
                task: updated_task,
                waiting: true,
                metadata: %{
                  task_continued: true,
                  task_id: updated_task.id,
                  waiting_for: updated_task.waiting_for
                }
              }}

            {:error, reason} ->
              Logger.error("Failed to continue task #{task_id}: #{reason}")
              {:error, reason}
          end
        else
          Logger.error("User #{user.id} attempted to access task #{task_id} belonging to user #{task.user_id}")
          {:error, "Task not found or access denied"}
        end

      {:error, :not_found} ->
        Logger.error("Task #{task_id} not found")
        {:error, "Task not found"}

      {:error, reason} ->
        Logger.error("Failed to retrieve task #{task_id}: #{reason}")
        {:error, reason}
    end
  end

  defp format_workflow_result(result, is_new_workflow) do
    # Format workflow engine results to match tool calling interface
    case result do
      %{message: message, details: details} ->
        {:ok, %{
          response: message,
          tools_used: extract_tools_from_details(details),
          context_used: [],
          task: nil,
          metadata: %{
            workflow_completed: true,
            is_new_workflow: is_new_workflow,
            details: details
          }
        }}

      %{message: message, steps_completed: steps_completed, final_result: final_result} ->
        {:ok, %{
          response: message,
          tools_used: extract_tools_from_final_result(final_result),
          context_used: Map.get(final_result, :context_used, []),
          task: nil,
          metadata: %{
            workflow_completed: true,
            is_new_workflow: is_new_workflow,
            steps_completed: steps_completed,
            final_result: final_result
          }
        }}

      %{response: response} = result ->
        # Handle results with response key (including needs_clarification, questions, etc.)
        {:ok, %{
          response: response,
          tools_used: [],
          context_used: [],
          task: nil,
          metadata: %{
            workflow_completed: true,
            is_new_workflow: is_new_workflow,
            needs_clarification: Map.get(result, :needs_clarification, false),
            questions: Map.get(result, :questions)
          }
        }}

      %{message: message} ->
        {:ok, %{
          response: message,
          tools_used: [],
          context_used: [],
          task: nil,
          metadata: %{
            workflow_completed: true,
            is_new_workflow: is_new_workflow
          }
        }}

      _ ->
        Logger.warning("Workflow completed with unexpected result format: #{inspect(result)}")
        {:ok, %{
          response: "Workflow processing completed. Check logs for detailed results.",
          tools_used: [],
          context_used: [],
          task: nil,
          metadata: %{
            workflow_completed: true,
            is_new_workflow: is_new_workflow,
            raw_result: result,
            warning: "Unexpected result format"
          }
        }}
    end
  end

  defp build_waiting_response(task) do
    case task.waiting_for do
      "email_reply" ->
        "I've sent the email and I'm now waiting for a reply. I'll automatically continue when a response is received."

      "calendar_response" ->
        "I've created the calendar event and sent invitations. I'm waiting for attendee responses."

      "external_approval" ->
        "The request has been submitted for approval. I'll continue when approval is received."

      "scheduled_time" ->
        scheduled_time = task.scheduled_for |> DateTime.to_string()
        "This task is scheduled to continue at #{scheduled_time}."

      "user_input" ->
        "I need additional information from you to continue. Please provide the requested details."

      _ ->
        "The task is waiting for an external event to continue. I'll automatically resume when the event occurs."
    end
  end

  defp extract_tools_from_details(details) when is_map(details) do
    # Extract tool usage information from workflow details
    tools_used = []

    # Check for various tool indicators in the details
    tools_used = if Map.has_key?(details, :message_id) do
      [%{tool: "email", function: "send", success: true, result: details} | tools_used]
    else
      tools_used
    end

    tools_used = if Map.has_key?(details, :event_id) do
      [%{tool: "calendar", function: "create_event", success: true, result: details} | tools_used]
    else
      tools_used
    end

    tools_used = if Map.has_key?(details, :contact_id) or Map.has_key?(details, :deal_id) do
      [%{tool: "hubspot", function: "create", success: true, result: details} | tools_used]
    else
      tools_used
    end

    tools_used
  end
  defp extract_tools_from_details(_), do: []

  defp extract_tools_from_final_result(final_result) when is_map(final_result) do
    # Extract tools from the final workflow result
    Map.get(final_result, :tools_used, [])
  end
  defp extract_tools_from_final_result(_), do: []
end
