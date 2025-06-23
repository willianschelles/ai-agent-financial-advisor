defmodule AiAgent.WorkflowEngine do
  @moduledoc """
  Dynamic workflow engine that intelligently handles complex multi-step processes.

  This engine analyzes user requests naturally and creates appropriate workflows
  without rigid patterns. It adapts to different business scenarios and uses
  available context to enhance interactions.
  """

  require Logger
  alias AiAgent.{TaskManager, LLM.ToolCalling}

  @doc """
  Create and execute a workflow based on user request.
  """
  def create_and_execute_workflow(user, request, opts \\ %{}) do
    Logger.info("Analyzing request for workflow: user #{user.id}")

    # Analyze the request to understand complexity and intent
    case analyze_request_complexity(user, request) do
      {:simple_action, action_type} ->
        # This doesn't need a workflow, just execute directly
        execute_simple_action(user, request, action_type, opts)

      {:complex_workflow, workflow_context} ->
        # Create and execute a multi-step workflow
        create_complex_workflow(user, request, workflow_context, opts)

      {:needs_clarification, questions} ->
        # Request needs clarification before proceeding
        {:ok, %{
          response: "I need some clarification: #{questions}",
          needs_clarification: true,
          questions: questions
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Execute an existing workflow task.
  """
  def execute_workflow(task, user, opts \\ %{}) do
    Logger.info("Executing workflow step for task #{task.id}")

    case task.status do
      "waiting" ->
        # Task is waiting for external input (like email reply)
        handle_waiting_task(task, user, opts)

      "active" ->
        # Task is ready for next step
        execute_next_workflow_step(task, user, opts)

      _ ->
        {:error, "Task #{task.id} is not in executable state"}
    end
  end

  @doc """
  Resume a workflow when an external event occurs (like webhook).
  """
  def resume_workflow(task, event_type, event_data, user) do
    Logger.info("Resuming workflow for task #{task.id} due to #{event_type}")

    # Update task with event data and continue
    case TaskManager.resume_task(task.id, event_data, "in_progress") do
      {:ok, updated_task} ->
        execute_workflow(updated_task, user)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp analyze_request_complexity(user, request) do
    # Use AI to understand the request naturally
    analysis_prompt = """
    Analyze this business request to determine if it needs a simple action or complex workflow:

    Request: "#{request}"

    Consider:
    - Single actions: Send one email, schedule one meeting, add one note
    - Complex workflows: Multi-step processes, waiting for responses, conditional actions

    Respond with one of:
    - "SIMPLE: email" - for direct email sending
    - "SIMPLE: calendar" - for direct meeting scheduling
    - "SIMPLE: crm" - for direct CRM actions
    - "COMPLEX: [brief description]" - for multi-step processes
    - "CLARIFY: [questions needed]" - if unclear

    Be concise and specific.
    """

    case ToolCalling.ask_with_tools(user, analysis_prompt, %{enable_tools: false}) do
      {:ok, result} ->
        parse_complexity_analysis(result.response, request)

      {:error, reason} ->
        Logger.warning("Analysis failed: #{reason}, using fallback")
        fallback_complexity_analysis(request)
    end
  end

  defp parse_complexity_analysis(response, request) do
    response_upper = String.upcase(response)

    cond do
      String.contains?(response_upper, "SIMPLE: EMAIL") ->
        {:simple_action, "email"}

      String.contains?(response_upper, "SIMPLE: CALENDAR") ->
        {:simple_action, "calendar"}

      String.contains?(response_upper, "SIMPLE: CRM") ->
        {:simple_action, "crm"}

      String.contains?(response_upper, "COMPLEX:") ->
        description = extract_after_colon(response, "COMPLEX:")
        {:complex_workflow, %{type: "multi_step", description: description, original_request: request}}

      String.contains?(response_upper, "CLARIFY:") ->
        questions = extract_after_colon(response, "CLARIFY:")
        {:needs_clarification, questions}

      true ->
        # Fallback analysis
        fallback_complexity_analysis(request)
    end
  end

  defp fallback_complexity_analysis(request) do
    request_lower = String.downcase(request)

    cond do
      # Multi-step indicators
      String.contains?(request_lower, ["and then", "wait for", "if they", "after"]) ->
        {:complex_workflow, %{type: "multi_step", original_request: request}}

      # Simple email
      String.contains?(request_lower, ["email", "send"]) and
      not String.contains?(request_lower, ["schedule", "meeting"]) ->
        {:simple_action, "email"}

      # Simple calendar
      String.contains?(request_lower, ["schedule", "meeting", "calendar"]) and
      not String.contains?(request_lower, ["email", "ask"]) ->
        {:simple_action, "calendar"}

      # Simple CRM
      String.contains?(request_lower, ["note", "contact", "crm"]) ->
        {:simple_action, "crm"}

      # Default to simple if unclear
      true ->
        {:simple_action, "unknown"}
    end
  end

  defp execute_simple_action(user, request, action_type, _opts) do
    Logger.info("Executing simple #{action_type} action")

    # Use the enhanced tool calling system to handle the request
    case ToolCalling.ask_with_tools(user, request) do
      {:ok, result} ->
        {:ok, %{
          response: result.response,
          tools_used: result.tools_used,
          action_type: action_type,
          workflow_type: "simple_action"
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_complex_workflow(user, request, workflow_context, opts) do
    Logger.info("Creating complex workflow")

    # Create a task to track the workflow
    task_data = %{
      user_id: user.id,
      original_request: request,
      workflow_type: "complex",
      workflow_state: workflow_context,
      next_step: "analyze_and_execute",
      status: "active"
    }

    case TaskManager.create_task(user, request, "multi_step_action", %{workflow_state: workflow_context}) do
      {:ok, task} ->
        # Execute the first step
        execute_workflow(task, user, opts)

      {:error, reason} ->
        {:error, "Failed to create workflow task: #{reason}"}
    end
  end

  defp handle_waiting_task(task, user, opts) do
    # Task is waiting for external input
    waiting_for = Map.get(task.workflow_state, "waiting_for", "unknown")

    case waiting_for do
      "email_reply" ->
        {:waiting, %{
          task: task,
          message: "Waiting for email reply",
          waiting_for: "email_reply"
        }}

      "calendar_response" ->
        {:waiting, %{
          task: task,
          message: "Waiting for calendar responses",
          waiting_for: "calendar_response"
        }}

      _ ->
        # Unknown waiting state, try to continue
        execute_next_workflow_step(task, user, opts)
    end
  end

  defp execute_next_workflow_step(task, user, opts) do
    next_step = task.next_step
    workflow_state = task.workflow_state

    case next_step do
      "analyze_and_execute" ->
        analyze_and_execute_complex_request(task, user, opts)

      "process_response" ->
        process_external_response(task, user, opts)

      "complete_workflow" ->
        complete_workflow(task, user, opts)

      _ ->
        Logger.error("Unknown workflow step: #{next_step}")
        {:error, "Unknown workflow step: #{next_step}"}
    end
  end

  defp analyze_and_execute_complex_request(task, user, opts) do
    request = task.original_request
    workflow_state = task.workflow_state

    # Break down the complex request into steps
    breakdown_prompt = """
    Break down this complex request into specific, actionable steps that can be executed using available tools:

    Request: "#{request}"

    Available tools:
    - Search documents/emails for information using semantic search
    - Send emails to specific recipients
    - Schedule calendar events
    - Update CRM contacts and notes

    Create specific steps that will accomplish the request. For search requests, be specific about what to search for. For email requests, specify the recipient and content type.

    Format your response as:
    Step 1: [specific action with details]
    Step 2: [specific action with details]
    etc.

    Example for a search+email request:
    Step 1: Search the document database for information about "Avenue Connections" including contact details, notes, and meeting records
    Step 2: Send an email to willianschelles@gmail.com with the compiled Avenue Connections information found in the search
    """

    case ToolCalling.ask_with_tools(user, breakdown_prompt, %{enable_tools: false}) do
      {:ok, result} ->
        steps = parse_workflow_steps(result.response)
        execute_workflow_steps(task, user, steps, opts)

      {:error, reason} ->
        Logger.error("Failed to analyze complex request: #{reason}")
        {:error, reason}
    end
  end

  defp parse_workflow_steps(response) do
    # Extract steps from the AI response
    response
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, "Step"))
    |> Enum.map(&String.trim/1)
    |> Enum.with_index(1)
    |> Enum.map(fn {step, index} ->
      %{
        step_number: index,
        description: step,
        status: "pending"
      }
    end)
  end

  defp execute_workflow_steps(task, user, steps, opts) do
    # Execute the first step
    case List.first(steps) do
      nil ->
        Logger.warning("No workflow steps generated for task #{task.id}")
        complete_workflow(task, user, opts)

      first_step ->
        Logger.info("Starting workflow execution with #{length(steps)} steps")
        execute_single_workflow_step(task, user, first_step, steps, opts)
    end
  end

  defp execute_single_workflow_step(task, user, current_step, all_steps, opts) do
    step_description = current_step.description
    
    Logger.info("Executing workflow step #{current_step.step_number}: #{step_description}")

    # Execute this step using the tool calling system with tools enabled but workflows disabled
    # to prevent infinite recursion while still allowing tool execution
    step_opts = %{
      enable_tools: true,
      enable_workflows: false,
      context_limit: 5,
      similarity_threshold: 0.3
    }
    
    case ToolCalling.ask_with_tools(user, step_description, step_opts) do
      {:ok, result} ->
        Logger.info("Step #{current_step.step_number} completed successfully. Tools used: #{length(Map.get(result, :tools_used, []))}")
        
        # Mark this step as completed and store the result
        updated_steps = mark_step_completed(all_steps, current_step.step_number, result)

        # Check if we need to wait for external response
        if requires_waiting?(result) do
          # Update task to waiting state
          updated_state = Map.merge(task.workflow_state, %{
            "steps" => updated_steps,
            "current_step_result" => result,
            "waiting_for" => determine_waiting_type(result)
          })

          case TaskManager.mark_task_waiting(task.id, determine_waiting_type(result), updated_state) do
            {:ok, updated_task} ->
              {:waiting, %{
                task: updated_task,
                message: "Step completed, waiting for external response",
                waiting_for: determine_waiting_type(result)
              }}

            {:error, reason} ->
              {:error, reason}
          end
        else
          # Continue to next step
          continue_to_next_step(task, user, updated_steps, result, opts)
        end

      {:error, reason} ->
        Logger.error("Failed to execute workflow step: #{reason}")
        {:error, reason}
    end
  end

  defp requires_waiting?(result) do
    # Check if the result indicates we need to wait for something
    tools_used = Map.get(result, :tools_used, [])

    Enum.any?(tools_used, fn tool ->
      tool_name = Map.get(tool, :tool, "") |> String.downcase()
      String.contains?(tool_name, "email") and
      String.contains?(Map.get(tool, :description, ""), ["sent", "request"])
    end)
  end

  defp determine_waiting_type(result) do
    tools_used = Map.get(result, :tools_used, [])

    cond do
      Enum.any?(tools_used, fn tool -> String.contains?(Map.get(tool, :tool, ""), "email") end) ->
        "email_reply"

      Enum.any?(tools_used, fn tool -> String.contains?(Map.get(tool, :tool, ""), "calendar") end) ->
        "calendar_response"

      true ->
        "unknown"
    end
  end

  defp mark_step_completed(steps, step_number, result \\ nil) do
    Enum.map(steps, fn step ->
      if step.step_number == step_number do
        step = %{step | status: "completed"}
        if result do
          Map.put(step, :result, result)
        else
          step
        end
      else
        step
      end
    end)
  end

  defp continue_to_next_step(task, user, updated_steps, last_result, opts) do
    # Find next pending step
    case Enum.find(updated_steps, fn step -> step.status == "pending" end) do
      nil ->
        # No more steps, complete workflow
        complete_workflow_with_results(task, user, updated_steps, last_result, opts)

      next_step ->
        # Execute next step
        execute_single_workflow_step(task, user, next_step, updated_steps, opts)
    end
  end

  defp complete_workflow(task, user, _opts) do
    Logger.info("Completing workflow for task #{task.id}")

    case TaskManager.update_task_status(task.id, "completed") do
      {:ok, _updated_task} ->
        {:ok, %{
          message: "Workflow completed successfully",
          task_id: task.id,
          workflow_type: "complex"
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp complete_workflow_with_results(task, user, steps, final_result, opts) do
    Logger.info("Completing workflow with results for task #{task.id}")

    updated_state = Map.merge(task.workflow_state, %{
      "steps" => steps,
      "final_result" => final_result,
      "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    })

    case TaskManager.update_task_status(task.id, "completed", %{workflow_state: updated_state}) do
      {:ok, _updated_task} ->
        {:ok, %{
          message: "Complex workflow completed successfully",
          task_id: task.id,
          steps_completed: length(steps),
          final_result: final_result,
          workflow_type: "complex"
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_external_response(task, user, opts) do
    Logger.info("Processing external response for task #{task.id}")

    workflow_state = task.workflow_state
    steps = Map.get(workflow_state, "steps", [])
    last_result = Map.get(workflow_state, "current_step_result", %{})

    # Continue from where we left off
    continue_to_next_step(task, user, steps, last_result, opts)
  end

  defp extract_after_colon(text, prefix) do
    case String.split(text, prefix, parts: 2) do
      [_, content] -> String.trim(content)
      _ -> ""
    end
  end
end
