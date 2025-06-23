defmodule AiAgent.WorkflowEngine do
  @moduledoc """
  Workflow engine for executing multi-step tasks and managing complex business processes.

  This module orchestrates the execution of tasks that may involve multiple tools,
  waiting periods, and conditional logic. It maintains state across sessions and
  can resume work when external events occur.
  """

  require Logger

  alias AiAgent.{TaskManager, Task}
  alias AiAgent.LLM.ToolCalling

  @doc """
  Execute a workflow for a given task.

  ## Parameters
  - task: Task struct to execute
  - user: User struct
  - opts: Execution options

  ## Returns
  - {:ok, result} if workflow completed successfully
  - {:waiting, task} if workflow is waiting for external event
  - {:error, reason} if workflow failed
  """
  def execute_workflow(%Task{} = task, user, opts \\ %{}) do
    Logger.info("Executing workflow for task #{task.id} (#{task.task_type})")

    case task.task_type do
      "email_workflow" -> execute_email_workflow(task, user, opts)
      "calendar_workflow" -> execute_calendar_workflow(task, user, opts)
      "hubspot_workflow" -> execute_hubspot_workflow(task, user, opts)
      "multi_step_action" -> execute_multi_step_workflow(task, user, opts)
      "composite_task" -> execute_composite_workflow(task, user, opts)
      _ -> execute_generic_workflow(task, user, opts)
    end
  end

  @doc """
  Resume a waiting workflow when an external event occurs.

  ## Parameters
  - task: Task that was waiting
  - event_type: Type of event that occurred
  - event_data: Data from the external event
  - user: User struct

  ## Returns
  - {:ok, result} if workflow completed after resumption
  - {:waiting, task} if workflow is still waiting for another event
  - {:error, reason} if resumption failed
  """
  def resume_workflow(%Task{} = task, event_type, event_data, user) do
    Logger.info("Resuming workflow for task #{task.id} due to #{event_type}")

    # Resume the task in the database
    case TaskManager.resume_task(task.id, %{event_type: event_type, data: event_data}) do
      {:ok, resumed_task} ->
        # Continue executing the workflow from where it left off
        execute_workflow(resumed_task, user, %{resuming: true, event_data: event_data})

      {:error, reason} ->
        Logger.error("Failed to resume task #{task.id}: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Create and execute a workflow from a user request.

  This is the main entry point for new workflow requests.
  """
  def create_and_execute_workflow(user, request, opts \\ %{}) do
    Logger.info("Creating and executing workflow for user #{user.id}")

    # Determine workflow type based on request content
    workflow_type = determine_workflow_type(request)

    # Create the task
    case TaskManager.create_task(user, request, workflow_type, opts) do
      {:ok, task} ->
        # Mark task as in progress
        {:ok, task} = TaskManager.update_task_status(task.id, "in_progress")

        # Execute the workflow
        execute_workflow(task, user, opts)

      {:error, reason} ->
        Logger.error("Failed to create workflow task: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Email workflow execution
  defp execute_email_workflow(task, user, opts) do
    Logger.debug("Executing email workflow for task #{task.id}")

    workflow_state = task.workflow_state
    next_step = task.next_step || "analyze_request"

    case next_step do
      "analyze_request" ->
        analyze_email_request(task, user, opts)

      "find_recipients" ->
        find_email_recipients(task, user, opts)

      "draft_email" ->
        draft_email_content(task, user, opts)

      "send_email" ->
        send_email_step(task, user, opts)

      "wait_for_reply" ->
        wait_for_email_reply(task, user, opts)

      "process_reply" ->
        process_email_reply(task, user, opts)

      "create_calendar_event" ->
        create_conditional_calendar_event(task, user, opts)

      _ ->
        Logger.error("Unknown email workflow step: #{next_step}")
        {:error, "Unknown workflow step"}
    end
  end

  # Calendar workflow execution
  defp execute_calendar_workflow(task, user, opts) do
    Logger.debug("Executing calendar workflow for task #{task.id}")

    next_step = task.next_step || "analyze_request"

    case next_step do
      "analyze_request" ->
        analyze_calendar_request(task, user, opts)

      "find_participants" ->
        find_meeting_participants(task, user, opts)

      "find_available_time" ->
        find_available_time_slots(task, user, opts)

      "create_event" ->
        create_calendar_event(task, user, opts)

      "send_invitations" ->
        send_calendar_invitations(task, user, opts)

      "wait_for_responses" ->
        wait_for_calendar_responses(task, user, opts)

      "process_responses" ->
        process_calendar_responses(task, user, opts)

      _ ->
        Logger.error("Unknown calendar workflow step: #{next_step}")
        {:error, "Unknown workflow step"}
    end
  end

  # HubSpot workflow execution
  defp execute_hubspot_workflow(task, user, opts) do
    Logger.debug("Executing HubSpot workflow for task #{task.id}")

    next_step = task.next_step || "analyze_request"

    case next_step do
      "analyze_request" ->
        analyze_hubspot_request(task, user, opts)

      "find_contacts" ->
        find_hubspot_contacts(task, user, opts)

      "create_contact" ->
        create_hubspot_contact(task, user, opts)

      "add_notes" ->
        add_hubspot_notes(task, user, opts)

      "create_deal" ->
        create_hubspot_deal(task, user, opts)

      "schedule_follow_up" ->
        schedule_hubspot_follow_up(task, user, opts)

      _ ->
        Logger.error("Unknown HubSpot workflow step: #{next_step}")
        {:error, "Unknown workflow step"}
    end
  end

  # Multi-step action workflow
  defp execute_multi_step_workflow(task, user, opts) do
    Logger.debug("Executing multi-step workflow for task #{task.id}")

    # Use AI to determine next steps based on the request and current state
    case determine_next_action(task, user) do
      {:ok, action} ->
        execute_determined_action(task, user, action, opts)

      {:error, reason} ->
        Logger.error("Failed to determine next action for task #{task.id}: #{reason}")
        fail_task(task, reason)
    end
  end

  # Composite workflow (multiple subtasks)
  defp execute_composite_workflow(task, user, opts) do
    Logger.debug("Executing composite workflow for task #{task.id}")

    # Create and execute subtasks based on the main task
    case break_down_composite_task(task, user) do
      {:ok, subtasks} ->
        execute_subtasks(task, subtasks, user, opts)

      {:error, reason} ->
        Logger.error("Failed to break down composite task #{task.id}: #{reason}")
        fail_task(task, reason)
    end
  end

  # Generic workflow for simple tasks
  defp execute_generic_workflow(task, user, opts) do
    Logger.debug("Executing generic workflow for task #{task.id}")

    # Use the existing tool calling system
    case ToolCalling.ask_with_tools(user, task.original_request, opts) do
      {:ok, result} ->
        # Mark task as completed
        TaskManager.update_task_status(task.id, "completed", %{
          workflow_state: %{
            "final_result" => result,
            "tools_used" => result.tools_used,
            "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
        })

        {:ok, result}

      {:error, reason} ->
        Logger.error("Generic workflow failed for task #{task.id}: #{reason}")
        fail_task(task, reason)
    end
  end

  # Email workflow steps

  defp analyze_email_request(task, user, _opts) do
    Logger.debug("Analyzing email request for task #{task.id}")

    # Use AI to analyze the email request and determine what needs to be done
    analysis_prompt = """
    Analyze this email request and determine the next steps:

    Request: #{task.original_request}

    Provide a JSON response with:
    - recipients: Who should receive the email
    - purpose: Purpose of the email
    - urgency: How urgent this email is
    - needs_approval: Whether this email needs approval before sending
    - next_step: What should happen next
    """

    case ToolCalling.ask_with_tools(user, analysis_prompt, %{enable_tools: false, enable_workflows: false}) do
      {:ok, result} ->
        # Parse the analysis and update workflow state
        workflow_state = Map.merge(task.workflow_state, %{
          "analysis" => result.response,
          "analysis_completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

        # Move to next step
        next_step = "find_recipients"
        update_workflow_and_continue(task, user, workflow_state, next_step)

      {:error, reason} ->
        fail_task(task, "Failed to analyze email request: #{reason}")
    end
  end

  defp find_email_recipients(task, user, _opts) do
    # Extract recipient information from the request
    case ToolCalling.execute_tool(user, "email", "email_find_contact", %{
      "name" => extract_recipient_name(task.original_request),
      "context_hint" => task.original_request
    }) do
      {:ok, result} ->
        workflow_state = Map.merge(task.workflow_state, %{
          "recipients_found" => result,
          "recipients_found_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

        next_step = "draft_email"
        update_workflow_and_continue(task, user, workflow_state, next_step)

      {:error, reason} ->
        fail_task(task, "Failed to find email recipients: #{reason}")
    end
  end

  defp draft_email_content(task, user, _opts) do
    # Draft the email based on the request and found recipients
    recipient_name = extract_recipient_name(task.original_request)
    purpose = extract_email_purpose(task.original_request)

    case ToolCalling.execute_tool(user, "email", "email_draft", %{
      "recipient_name" => recipient_name,
      "purpose" => purpose,
      "key_points" => extract_key_points(task.original_request),
      "tone" => "professional"
    }) do
      {:ok, result} ->
        workflow_state = Map.merge(task.workflow_state, %{
          "email_draft" => result,
          "draft_created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

        next_step = "send_email"
        update_workflow_and_continue(task, user, workflow_state, next_step)

      {:error, reason} ->
        fail_task(task, "Failed to draft email: #{reason}")
    end
  end

  defp send_email_step(task, user, _opts) do
    # Send the drafted email
    recipients = get_recipients_from_workflow(task)
    draft = get_in(task.workflow_state, ["email_draft", "draft"])
    subject = extract_email_subject(task.original_request)

    Logger.debug("Email send step - recipients: #{inspect(recipients)}, draft: #{inspect(draft)}, subject: #{inspect(subject)}")

    # Ensure we have a body - fallback to a simple message if draft is nil
    body = case draft do
      nil ->
        Logger.warn("No draft found in workflow state, creating simple message")
        create_simple_availability_message(task.original_request)
      draft when is_binary(draft) -> draft
      _ ->
        Logger.warn("Invalid draft format: #{inspect(draft)}")
        create_simple_availability_message(task.original_request)
    end

    case ToolCalling.execute_tool(user, "email", "email_send", %{
      "to" => recipients,
      "subject" => subject,
      "body" => body
    }) do
      {:ok, result} ->
        workflow_state = Map.merge(task.workflow_state, %{
          "email_sent" => result,
          "sent_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

        # Check if we need to wait for a reply
        if needs_reply?(task.original_request) do
          TaskManager.mark_task_waiting(task.id, "email_reply", %{
            "message_id" => result.message_id,
            "recipients" => recipients
          })
          {:waiting, task}
        else
          TaskManager.update_task_status(task.id, "completed", %{workflow_state: workflow_state})
          {:ok, %{message: "Email sent successfully", details: result}}
        end

      {:error, reason} ->
        fail_task(task, "Failed to send email: #{reason}")
    end
  end

  defp wait_for_email_reply(task, user, opts) do
    # This step is reached when resuming from an email reply event
    event_data = Map.get(opts, :event_data, %{})

    workflow_state = Map.merge(task.workflow_state, %{
      "reply_received" => event_data,
      "reply_received_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    })

    next_step = "process_reply"
    update_workflow_and_continue(task, user, workflow_state, next_step)
  end

  defp process_email_reply(task, user, _opts) do
    # Process the received email reply
    reply_data = get_in(task.workflow_state, ["reply_received"])

    # Check if this was a meeting request that might need calendar event creation
    if is_meeting_request_workflow?(task.original_request) do
      # Analyze the reply to see if it's an acceptance
      analysis_prompt = """
      Analyze this reply to a meeting request email:

      Original request: #{task.original_request}
      Reply content: #{inspect(reply_data)}

      Respond with JSON:
      {
        "meeting_accepted": true/false,
        "proposed_time": "time if mentioned",
        "response_type": "accepted/declined/counter_proposal/unclear"
      }
      """

      case ToolCalling.ask_with_tools(user, analysis_prompt, %{enable_tools: false, enable_workflows: false}) do
        {:ok, result} ->
          # Try to parse the response as JSON to check for acceptance
          case Jason.decode(result.response) do
            {:ok, %{"meeting_accepted" => true}} ->
              workflow_state = Map.merge(task.workflow_state, %{
                "reply_analysis" => result.response,
                "meeting_accepted" => true
              })

              next_step = "create_calendar_event"
              update_workflow_and_continue(task, user, workflow_state, next_step)

            {:ok, %{"meeting_accepted" => false}} ->
              workflow_state = Map.merge(task.workflow_state, %{
                "reply_analysis" => result.response,
                "meeting_declined" => true,
                "task_completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
              })

              TaskManager.update_task_status(task.id, "completed", %{workflow_state: workflow_state})
              {:ok, %{message: "Meeting was declined, no calendar event created", details: result}}

            _ ->
              # Couldn't parse response or unclear, complete the task
              workflow_state = Map.merge(task.workflow_state, %{
                "reply_analysis" => result.response,
                "task_completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
              })

              TaskManager.update_task_status(task.id, "completed", %{workflow_state: workflow_state})
              {:ok, %{message: "Email workflow completed - unclear response", details: result}}
          end

        {:error, reason} ->
          fail_task(task, "Failed to analyze email reply: #{reason}")
      end
    else
      # Regular email workflow - just complete
      analysis_prompt = """
      A reply was received for this email task:

      Original request: #{task.original_request}
      Reply content: #{inspect(reply_data)}

      Determine if any follow-up actions are needed or if the task is complete.
      """

      case ToolCalling.ask_with_tools(user, analysis_prompt, %{enable_tools: false, enable_workflows: false}) do
        {:ok, result} ->
          workflow_state = Map.merge(task.workflow_state, %{
            "reply_analysis" => result.response,
            "task_completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          })

          TaskManager.update_task_status(task.id, "completed", %{workflow_state: workflow_state})
          {:ok, %{message: "Email workflow completed", analysis: result.response}}

        {:error, reason} ->
          fail_task(task, "Failed to process email reply: #{reason}")
      end
    end
  end

  defp create_conditional_calendar_event(task, user, _opts) do
    # Create a calendar event based on the meeting acceptance
    meeting_info = extract_meeting_info_from_request(task.original_request)

    case ToolCalling.execute_tool(user, "calendar", "calendar_create_event", %{
      "title" => meeting_info.title,
      "start_time" => meeting_info.start_time,
      "end_time" => meeting_info.end_time,
      "attendees" => meeting_info.attendees,
      "description" => "Meeting scheduled following email confirmation"
    }) do
      {:ok, result} ->
        workflow_state = Map.merge(task.workflow_state, %{
          "calendar_event_created" => result,
          "event_created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "task_completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

        TaskManager.update_task_status(task.id, "completed", %{workflow_state: workflow_state})
        {:ok, %{message: "Meeting accepted and calendar event created", details: result}}

      {:error, reason} ->
        fail_task(task, "Failed to create calendar event: #{reason}")
    end
  end

  defp is_meeting_request_workflow?(request) do
    request_lower = String.downcase(request)
    meeting_indicators = [
      "meeting", "meet", "appointment", "call", "conference", "discussion",
      "calendar", "schedule", "available", "availability"
    ]

    Enum.any?(meeting_indicators, fn indicator ->
      String.contains?(request_lower, indicator)
    end)
  end

  defp extract_meeting_info_from_request(request) do
    # Extract meeting details from the original request
    # This is a simplified version - in production you'd want more sophisticated parsing

    # Try to extract time information
    time_patterns = [
      ~r/tomorrow (\d+)-(\d+)([ap]m)/i,
      ~r/(\d+):(\d+)\s*([ap]m)/i,
      ~r/(\d+)\s*([ap]m)/i
    ]

    {start_time, end_time} = case Enum.find_value(time_patterns, fn pattern ->
      case Regex.run(pattern, request) do
        [_, start_hour, end_hour, period] when byte_size(end_hour) > 0 ->
          # Handle ranges like "4-5pm"
          {parse_time(start_hour, period), parse_time(end_hour, period)}
        [_, hour, minute, period] ->
          # Handle specific times like "4:30pm"
          start = parse_time_with_minute(hour, minute, period)
          end_time = add_hour(start)
          {start, end_time}
        [_, hour, period] ->
          # Handle hour-only like "4pm"
          start = parse_time(hour, period)
          end_time = add_hour(start)
          {start, end_time}
        _ -> nil
      end
    end) do
      {start, end_time} when not is_nil(start) -> {start, end_time}
      _ -> {default_meeting_time(), default_meeting_end_time()}
    end

    # Extract attendee from request (simple name extraction)
    attendee_email = extract_attendee_email(request)

    %{
      title: "Meeting",
      start_time: start_time,
      end_time: end_time,
      attendees: [attendee_email],
      description: "Meeting scheduled via email workflow"
    }
  end

  defp parse_time(hour_str, period) do
    hour = String.to_integer(hour_str)
    hour = if String.downcase(period) == "pm" and hour != 12, do: hour + 12, else: hour
    hour = if String.downcase(period) == "am" and hour == 12, do: 0, else: hour

    # Default to tomorrow at the specified hour
    tomorrow = DateTime.utc_now() |> DateTime.add(1, :day)
    beginning_of_day = %{tomorrow | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
    beginning_of_day
    |> DateTime.add(hour * 3600, :second)
    |> DateTime.to_iso8601()
  end

  defp parse_time_with_minute(hour_str, minute_str, period) do
    hour = String.to_integer(hour_str)
    minute = String.to_integer(minute_str)
    hour = if String.downcase(period) == "pm" and hour != 12, do: hour + 12, else: hour
    hour = if String.downcase(period) == "am" and hour == 12, do: 0, else: hour

    tomorrow = DateTime.utc_now() |> DateTime.add(1, :day)
    beginning_of_day = %{tomorrow | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
    beginning_of_day
    |> DateTime.add(hour * 3600 + minute * 60, :second)
    |> DateTime.to_iso8601()
  end

  defp add_hour(iso_datetime) do
    {:ok, dt, _} = DateTime.from_iso8601(iso_datetime)
    dt
    |> DateTime.add(3600, :second)
    |> DateTime.to_iso8601()
  end

  defp default_meeting_time do
    tomorrow = DateTime.utc_now() |> DateTime.add(1, :day)
    beginning_of_day = %{tomorrow | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
    beginning_of_day
    |> DateTime.add(16 * 3600, :second)  # 4 PM
    |> DateTime.to_iso8601()
  end

  defp default_meeting_end_time do
    tomorrow = DateTime.utc_now() |> DateTime.add(1, :day)
    beginning_of_day = %{tomorrow | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
    beginning_of_day
    |> DateTime.add(17 * 3600, :second)  # 5 PM
    |> DateTime.to_iso8601()
  end

  defp extract_attendee_email(request) do
    # Simple name extraction - in production you'd want to look up actual email addresses
    # from contacts or ask for clarification

    # Try to extract a name after "to" or "with"
    name_patterns = [
      ~r/(?:to|with)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)/,
      ~r/([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)/
    ]

    case Enum.find_value(name_patterns, fn pattern ->
      case Regex.run(pattern, request) do
        [_, name] -> name
        _ -> nil
      end
    end) do
      nil -> "attendee@example.com"  # Fallback
      name ->
        # Convert name to email (this is a placeholder - you'd want to look this up)
        name
        |> String.downcase()
        |> String.replace(" ", ".")
        |> Kernel.<>("@example.com")
    end
  end

  # Calendar workflow steps (simplified for brevity)

  defp analyze_calendar_request(task, user, _opts) do
    # Similar to email analysis but for calendar events
    workflow_state = Map.merge(task.workflow_state, %{
      "request_type" => "calendar",
      "analyzed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    })

    next_step = "find_participants"
    update_workflow_and_continue(task, user, workflow_state, next_step)
  end

  defp find_meeting_participants(task, user, _opts) do
    # Extract participants from the request
    next_step = "find_available_time"
    update_workflow_and_continue(task, user, task.workflow_state, next_step)
  end

  defp find_available_time_slots(task, user, _opts) do
    # Find available time slots for the meeting
    next_step = "create_event"
    update_workflow_and_continue(task, user, task.workflow_state, next_step)
  end

  defp create_calendar_event(task, user, _opts) do
    # Create the calendar event using the calendar tool
    event_data = extract_calendar_data(task.original_request)

    case ToolCalling.execute_tool(user, "calendar", "calendar_create_event", event_data) do
      {:ok, result} ->
        workflow_state = Map.merge(task.workflow_state, %{
          "event_created" => result,
          "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

        TaskManager.update_task_status(task.id, "completed", %{workflow_state: workflow_state})
        {:ok, %{message: "Calendar event created successfully", details: result}}

      {:error, reason} ->
        fail_task(task, "Failed to create calendar event: #{reason}")
    end
  end

  defp send_calendar_invitations(task, user, _opts) do
    # Send calendar invitations
    next_step = "wait_for_responses"
    update_workflow_and_continue(task, user, task.workflow_state, next_step)
  end

  defp wait_for_calendar_responses(task, user, _opts) do
    # Wait for calendar responses
    next_step = "process_responses"
    update_workflow_and_continue(task, user, task.workflow_state, next_step)
  end

  defp process_calendar_responses(task, user, _opts) do
    # Process calendar responses
    TaskManager.update_task_status(task.id, "completed")
    {:ok, %{message: "Calendar workflow completed"}}
  end

  # HubSpot workflow steps (simplified)

  defp analyze_hubspot_request(task, user, _opts) do
    next_step = "find_contacts"
    update_workflow_and_continue(task, user, task.workflow_state, next_step)
  end

  defp find_hubspot_contacts(task, user, _opts) do
    next_step = "create_contact"
    update_workflow_and_continue(task, user, task.workflow_state, next_step)
  end

  defp create_hubspot_contact(task, user, _opts) do
    next_step = "add_notes"
    update_workflow_and_continue(task, user, task.workflow_state, next_step)
  end

  defp add_hubspot_notes(task, user, _opts) do
    TaskManager.update_task_status(task.id, "completed")
    {:ok, %{message: "HubSpot workflow completed"}}
  end

  defp create_hubspot_deal(task, user, _opts) do
    TaskManager.update_task_status(task.id, "completed")
    {:ok, %{message: "HubSpot deal created"}}
  end

  defp schedule_hubspot_follow_up(task, user, _opts) do
    TaskManager.update_task_status(task.id, "completed")
    {:ok, %{message: "HubSpot follow-up scheduled"}}
  end

  # Helper functions

  defp determine_workflow_type(request) do
    request_lower = String.downcase(request)

    cond do
      String.contains?(request_lower, ["email", "send", "message", "write"]) ->
        "email_workflow"

      String.contains?(request_lower, ["schedule", "calendar", "meeting", "appointment"]) ->
        "calendar_workflow"

      String.contains?(request_lower, ["hubspot", "crm", "contact", "deal", "note"]) ->
        "hubspot_workflow"

      String.contains?(request_lower, ["and", "then", "after", "following"]) ->
        "multi_step_action"

      true ->
        "multi_step_action"
    end
  end

  defp determine_next_action(task, user) do
    # Use AI to determine the next action based on the task state
    prompt = """
    Determine the next action for this task:

    Original request: #{task.original_request}
    Completed steps: #{inspect(task.steps_completed)}
    Current workflow state: #{inspect(task.workflow_state)}

    What should be done next?
    """

    case ToolCalling.ask_with_tools(user, prompt, %{enable_tools: false, enable_workflows: false}) do
      {:ok, result} ->
        {:ok, result.response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_determined_action(task, user, action, opts) do
    # Execute the action determined by AI
    case ToolCalling.ask_with_tools(user, action, opts) do
      {:ok, result} ->
        TaskManager.update_task_status(task.id, "completed", %{
          workflow_state: Map.merge(task.workflow_state, %{
            "final_action" => action,
            "final_result" => result
          })
        })

        {:ok, result}

      {:error, reason} ->
        fail_task(task, reason)
    end
  end

  defp break_down_composite_task(task, user) do
    # Break down a composite task into subtasks
    {:ok, []} # Simplified for now
  end

  defp execute_subtasks(task, subtasks, user, opts) do
    # Execute subtasks in sequence or parallel
    TaskManager.update_task_status(task.id, "completed")
    {:ok, %{message: "Composite task completed"}}
  end

  defp update_workflow_and_continue(task, user, workflow_state, next_step) do
    # Update the task workflow state and continue to next step
    case TaskManager.update_task_status(task.id, "in_progress", %{
      workflow_state: workflow_state,
      next_step: next_step
    }) do
      {:ok, updated_task} ->
        # Add the current step as completed
        TaskManager.add_completed_step(task.id, task.next_step || "initial")

        # Continue with the next step
        execute_workflow(updated_task, user)

      {:error, reason} ->
        fail_task(task, "Failed to update workflow state: #{inspect(reason)}")
    end
  end

  defp fail_task(task, reason) do
    Logger.error("Task #{task.id} failed: #{reason}")
    TaskManager.update_task_status(task.id, "failed", %{failure_reason: reason})
    {:error, reason}
  end

  # Text extraction helpers

  defp extract_recipient_name(request) do
    # Simple pattern matching to extract recipient name
    # Look for patterns like "to John Smith" or "to Maria Johnson"
    patterns = [
      # First try to match full name with boundary words
      ~r/(?:email|send.*to|to)\s+([A-Z][a-z]+\s+[A-Z][a-z]+)(?:\s+(?:asking|about|telling|regarding|and|if))/i,
      # Then try full name without boundary
      ~r/(?:email|send.*to|to)\s+([A-Z][a-z]+\s+[A-Z][a-z]+)(?:\s|$)/i,
      # Single name with boundary words
      ~r/(?:email|send.*to|to)\s+([A-Z][a-z]+)(?:\s+(?:asking|about|telling|regarding|and|if))/i,
      # Single name without boundary
      ~r/(?:email|send.*to|to)\s+([A-Z][a-z]+)(?:\s|$)/i
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, request) do
        [_, name] -> String.trim(name)
        _ -> nil
      end
    end) || "Unknown"
  end

  defp extract_email_purpose(request) do
    cond do
      String.contains?(String.downcase(request), "follow") -> "follow up on meeting"
      String.contains?(String.downcase(request), "schedule") -> "schedule appointment"
      String.contains?(String.downcase(request), "update") -> "send portfolio update"
      true -> "general inquiry"
    end
  end

  defp extract_email_subject(request) do
    String.slice(request, 0, 50) <> "..."
  end

  defp extract_key_points(request) do
    [request]
  end

  defp extract_calendar_data(request) do
    %{
      "title" => "Meeting",
      "start_time" => "2024-01-15T14:00:00-05:00",
      "end_time" => "2024-01-15T15:00:00-05:00",
      "description" => request
    }
  end

  defp get_recipients_from_workflow(task) do
    IO.inspect(task, label: "Task Details")
    IO.inspect(task.workflow_state, label: "Workflow State")
    IO.inspect(get_in(task.workflow_state, ["recipients_found", :emails_found]), label: "Emails Found")
    case get_in(task.workflow_state, ["recipients_found", :emails_found]) do
      emails when is_list(emails) and length(emails) > 0 ->
        email_addresses = Enum.map(emails, & &1[:email])
        Logger.debug("Found recipient emails from workflow: #{inspect(email_addresses)}")
        email_addresses
      _ ->
        # Try to extract email from the original request as a last resort
        extracted_name = extract_recipient_name(task.original_request)
        Logger.warn("No emails found in workflow state for '#{extracted_name}', attempting direct extraction from request")

        case extract_email_from_request(task.original_request) do
          nil ->
            Logger.error("Could not find any email address for recipient. Using demo email as last resort.")
            ["demo@example.com"]
          email ->
            Logger.info("Found email '#{email}' directly from request text")
            [email]
        end
    end
  end

  defp extract_email_from_request(request) do
    # Try to find email addresses directly in the request text
    case Regex.run(~r/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/, request) do
      [email] -> email
      _ -> nil
    end
  end

  defp needs_reply?(request) do
    request_lower = String.downcase(request)
    String.contains?(request_lower, ["reply", "response", "answer", "confirm", "if", "availability", "available"])
  end

  defp create_simple_availability_message(request) do
    # Extract the meeting time from the request
    time_info = case Regex.run(~r/tomorrow (\d+-?\d*[ap]m)/i, request) do
      [_, time] -> "tomorrow #{time}"
      _ -> "tomorrow"
    end

    """
    Hi there,

    I hope this email finds you well.

    I wanted to reach out to check if you're available for a meeting #{time_info}. Please let me know if this time works for you or if you'd prefer to schedule for a different time.

    Looking forward to hearing from you.

    Best regards
    """
  end
end
