defmodule AiAgent.SimpleWorkflowEngine do
  @moduledoc """
  Simplified workflow engine for email->calendar workflows.
  
  This handles the specific flow:
  1. User requests: "send email to X asking about meeting"
  2. Send email -> Save task as waiting for reply
  3. Webhook receives reply -> Resume task
  4. Analyze reply -> Create calendar event if accepted
  """
  
  require Logger
  alias AiAgent.{SimpleTaskManager, LLM.ToolCalling}
  
  @doc """
  Process a user request that involves email->calendar workflow.
  """
  def handle_email_calendar_request(user, request) do
    Logger.info("Processing email->calendar request for user #{user.id}")
    
    # Step 1: Detect if this is an email->calendar workflow
    if is_email_calendar_workflow?(request) do
      # Step 2: Extract workflow data
      workflow_data = extract_workflow_data(request)
      
      # Step 3: Create task
      case SimpleTaskManager.create_email_calendar_task(user, request, workflow_data) do
        {:ok, task} ->
          # Step 4: Execute the workflow
          execute_workflow_step(task, user)
        
        {:error, reason} ->
          Logger.error("Failed to create email->calendar task: #{inspect(reason)}")
          {:error, "Failed to create task: #{inspect(reason)}"}
      end
    else
      # Not an email->calendar workflow, handle normally
      {:not_email_calendar_workflow, request}
    end
  end
  
  @doc """
  Resume a workflow when a webhook is received.
  """
  def resume_workflow_from_webhook(user_id, email_data) do
    Logger.info("Resuming workflow from webhook for user #{user_id}")
    
    # Find waiting tasks that match this email
    waiting_tasks = SimpleTaskManager.find_waiting_tasks_for_email(user_id, email_data)
    
    results = Enum.map(waiting_tasks, fn task ->
      case resume_task_execution(task, email_data) do
        {:ok, result} ->
          Logger.info("Successfully resumed task #{task.id}")
          {:ok, task.id, result}
        
        {:error, reason} ->
          Logger.error("Failed to resume task #{task.id}: #{reason}")
          SimpleTaskManager.fail_task(task.id, "Failed to resume: #{reason}")
          {:error, task.id, reason}
      end
    end)
    
    successful_resumes = Enum.count(results, fn {status, _, _} -> status == :ok end)
    Logger.info("Resumed #{successful_resumes} out of #{length(results)} tasks")
    
    {:ok, results}
  end
  
  # Private functions
  
  defp is_email_calendar_workflow?(request) do
    request_lower = String.downcase(request)
    
    # Check for email keywords AND calendar/meeting keywords
    has_email = String.contains?(request_lower, ["email", "send", "message", "write to"])
    has_meeting = String.contains?(request_lower, ["meeting", "available", "schedule", "appointment", "calendar", "meet"])
    
    has_email and has_meeting
  end
  
  defp extract_workflow_data(request) do
    %{
      "recipient_name" => extract_recipient_name(request),
      "meeting_details" => extract_meeting_details(request),
      "email_purpose" => "meeting_request",
      "extracted_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
  
  defp extract_recipient_name(request) do
    patterns = [
      ~r/(?:email|send.*to|to)\s+([A-Z][a-z]+\s+[A-Z][a-z]+)(?:\s+(?:asking|about|if))/i,
      ~r/(?:email|send.*to|to)\s+([A-Z][a-z]+\s+[A-Z][a-z]+)/i,
      ~r/(?:email|send.*to|to)\s+([A-Z][a-z]+)/i
    ]
    
    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, request) do
        [_, name] -> String.trim(name)
        _ -> nil
      end
    end) || "Unknown"
  end
  
  defp extract_meeting_details(request) do
    # Extract time patterns
    time_patterns = [
      ~r/tomorrow (\d+-?\d*[ap]m)/i,
      ~r/(\d+:\d+[ap]m)/i,
      ~r/(\d+[ap]m)/i
    ]
    
    time_info = Enum.find_value(time_patterns, fn pattern ->
      case Regex.run(pattern, request) do
        [_, time] -> time
        _ -> nil
      end
    end)
    
    %{
      "time_mentioned" => time_info,
      "original_request" => request
    }
  end
  
  defp execute_workflow_step(task, user) do
    case task.next_step do
      "send_email" ->
        send_email_step(task, user)
      
      "process_reply" ->
        process_reply_step(task, user)
      
      "create_calendar_event" ->
        create_calendar_step(task, user)
      
      _ ->
        Logger.error("Unknown workflow step: #{task.next_step}")
        SimpleTaskManager.fail_task(task.id, "Unknown workflow step: #{task.next_step}")
        {:error, "Unknown workflow step"}
    end
  end
  
  defp send_email_step(task, user) do
    Logger.info("Executing send_email step for task #{task.id}")
    
    workflow_state = task.workflow_state
    recipient_name = Map.get(workflow_state, "recipient_name", "Unknown")
    
    # Find the recipient's email
    case ToolCalling.execute_tool(user, "email", "email_find_contact", %{
      "name" => recipient_name,
      "context_hint" => task.original_request
    }) do
      {:ok, contact_result} ->
        case get_in(contact_result, [:emails_found]) do
          emails when is_list(emails) and length(emails) > 0 ->
            recipient_email = List.first(emails)[:email]
            
            # Draft and send email
            case draft_and_send_email(user, task, recipient_email, recipient_name) do
              {:ok, email_result} ->
                # Mark task as waiting for reply
                SimpleTaskManager.mark_waiting_for_reply(task.id, email_result)
                {:ok, %{message: "Email sent, waiting for reply", email_data: email_result}}
              
              {:error, reason} ->
                SimpleTaskManager.fail_task(task.id, "Failed to send email: #{reason}")
                {:error, reason}
            end
          
          _ ->
            error_msg = "No email found for recipient: #{recipient_name}"
            SimpleTaskManager.fail_task(task.id, error_msg)
            {:error, error_msg}
        end
      
      {:error, reason} ->
        SimpleTaskManager.fail_task(task.id, "Failed to find contact: #{reason}")
        {:error, reason}
    end
  end
  
  defp draft_and_send_email(user, task, recipient_email, recipient_name) do
    meeting_details = get_in(task.workflow_state, ["meeting_details"])
    time_mentioned = Map.get(meeting_details, "time_mentioned", "tomorrow")
    
    # Create professional email subject based on context
    subject = generate_professional_subject(task, recipient_name, time_mentioned)
    body = """
    Hi #{recipient_name},

    I hope this email finds you well.

    I wanted to reach out to check if you're available for a meeting #{time_mentioned}. Please let me know if this time works for you or if you'd prefer to schedule for a different time.

    Looking forward to hearing from you.

    Best regards
    """
    
    # Send email
    ToolCalling.execute_tool(user, "email", "email_send", %{
      "to" => [recipient_email],
      "subject" => subject,
      "body" => body
    })
  end

  defp generate_professional_subject(task, recipient_name, time_mentioned) do
    # Extract the original request context
    original_request = task.request_params["message"] || task.workflow_state["original_request"] || ""
    
    # Analyze the request to determine the best subject
    cond do
      String.contains?(String.downcase(original_request), ["meeting", "schedule", "availability"]) ->
        format_meeting_subject(recipient_name, time_mentioned)
      
      String.contains?(String.downcase(original_request), ["follow up", "follow-up", "checking in"]) ->
        "Following Up - #{recipient_name}"
      
      String.contains?(String.downcase(original_request), ["discussion", "discuss", "talk about"]) ->
        "Discussion Request - #{extract_topic(original_request)}"
      
      String.contains?(String.downcase(original_request), ["question", "inquiry", "ask about"]) ->
        "Inquiry - #{extract_topic(original_request)}"
      
      true ->
        # Default professional subject
        "Meeting Request - #{format_time_for_subject(time_mentioned)}"
    end
  end

  defp format_meeting_subject(_recipient_name, time_mentioned) do
    formatted_time = format_time_for_subject(time_mentioned)
    "Meeting Request - #{formatted_time}"
  end

  defp format_time_for_subject(time_mentioned) do
    # Convert casual time mentions to more professional format
    time_mentioned
    |> String.replace("tomorrow", "Tomorrow")
    |> String.replace("next week", "Next Week")
    |> String.replace("this week", "This Week")
    |> String.replace("today", "Today")
  end

  defp extract_topic(original_request) do
    # Simple topic extraction - could be enhanced with NLP
    cond do
      String.contains?(String.downcase(original_request), ["investment", "portfolio"]) ->
        "Investment Discussion"
      
      String.contains?(String.downcase(original_request), ["retirement", "planning"]) ->
        "Retirement Planning"
      
      String.contains?(String.downcase(original_request), ["review", "account"]) ->
        "Account Review"
      
      String.contains?(String.downcase(original_request), ["strategy", "strategies"]) ->
        "Strategy Discussion"
      
      true ->
        "Scheduling Discussion"
    end
  end
  
  defp resume_task_execution(task, email_data) do
    Logger.info("Resuming execution for task #{task.id}")
    
    # Resume the task with reply data
    case SimpleTaskManager.resume_task_with_reply(task.id, email_data) do
      {:ok, updated_task} ->
        # Get user to continue execution
        case AiAgent.Repo.get(AiAgent.User, updated_task.user_id) do
          nil ->
            {:error, "User not found"}
          
          user ->
            # Continue with next step
            execute_workflow_step(updated_task, user)
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp process_reply_step(task, user) do
    Logger.info("Processing reply for task #{task.id}")
    
    reply_data = get_in(task.workflow_state, ["reply_data"])
    
    # Analyze the reply to determine if meeting was accepted
    analysis_prompt = """
    Analyze this email reply to a meeting request:

    Original request: #{task.original_request}
    Reply from: #{Map.get(reply_data, :from, "unknown")}
    Reply subject: #{Map.get(reply_data, :subject, "unknown")}
    Reply body: #{Map.get(reply_data, :body, "unknown")}

    Determine if the meeting was accepted. Respond with only "ACCEPTED" or "DECLINED" or "UNCLEAR".
    """
    
    case ToolCalling.ask_with_tools(user, analysis_prompt, %{enable_tools: false, enable_workflows: false}) do
      {:ok, result} ->
        response = String.upcase(String.trim(result.response))
        
        case response do
          "ACCEPTED" ->
            # Move to calendar creation step
            Logger.info("Meeting accepted, proceeding to create calendar event")
            execute_workflow_step(%{task | next_step: "create_calendar_event"}, user)
          
          "DECLINED" ->
            # Complete task without calendar
            SimpleTaskManager.complete_task_with_calendar(task.id, %{
              "calendar_created" => false,
              "reason" => "Meeting declined"
            })
            {:ok, %{message: "Meeting was declined, task completed"}}
          
          _ ->
            # Unclear response, complete task
            SimpleTaskManager.complete_task_with_calendar(task.id, %{
              "calendar_created" => false,
              "reason" => "Unclear response"
            })
            {:ok, %{message: "Unclear response, task completed"}}
        end
      
      {:error, reason} ->
        Logger.error("Failed to analyze reply: #{reason}")
        SimpleTaskManager.fail_task(task.id, "Failed to analyze reply: #{reason}")
        {:error, reason}
    end
  end
  
  defp create_calendar_step(task, user) do
    Logger.info("Creating calendar event for task #{task.id}")
    
    workflow_state = task.workflow_state
    recipient_name = Map.get(workflow_state, "recipient_name")
    meeting_details = Map.get(workflow_state, "meeting_details", %{})
    time_mentioned = Map.get(meeting_details, "time_mentioned", "tomorrow 4-5pm")
    
    # Parse time and create calendar event
    {start_time, end_time} = parse_meeting_time(time_mentioned)
    
    # Get recipient email from the email data
    email_data = Map.get(workflow_state, "email_data", %{})
    recipient_email = List.first(Map.get(email_data, "to", []))
    
    calendar_data = %{
      "title" => "Meeting with #{recipient_name}",
      "start_time" => start_time,
      "end_time" => end_time,
      "attendees" => [recipient_email],
      "description" => "Meeting scheduled via email workflow"
    }
    
    case ToolCalling.execute_tool(user, "calendar", "calendar_create_event", calendar_data) do
      {:ok, calendar_result} ->
        # Complete the task
        SimpleTaskManager.complete_task_with_calendar(task.id, calendar_result)
        {:ok, %{message: "Calendar event created successfully", calendar_data: calendar_result}}
      
      {:error, reason} ->
        Logger.error("Failed to create calendar event: #{reason}")
        SimpleTaskManager.fail_task(task.id, "Failed to create calendar event: #{reason}")
        {:error, reason}
    end
  end
  
  defp parse_meeting_time(time_mentioned) do
    # Simple time parsing - can be enhanced
    case Regex.run(~r/(\d+)-(\d+)([ap]m)/i, time_mentioned) do
      [_, start_hour, end_hour, period] ->
        start_time = format_time_for_calendar(start_hour, period)
        end_time = format_time_for_calendar(end_hour, period)
        {start_time, end_time}
      
      _ ->
        # Default to 1 hour meeting starting at 4 PM tomorrow
        tomorrow = DateTime.utc_now() |> DateTime.add(1, :day)
        start_time = %{tomorrow | hour: 16, minute: 0, second: 0, microsecond: {0, 0}} |> DateTime.to_iso8601()
        end_time = %{tomorrow | hour: 17, minute: 0, second: 0, microsecond: {0, 0}} |> DateTime.to_iso8601()
        {start_time, end_time}
    end
  end
  
  defp format_time_for_calendar(hour_str, period) do
    hour = String.to_integer(hour_str)
    hour = if String.downcase(period) == "pm" and hour != 12, do: hour + 12, else: hour
    hour = if String.downcase(period) == "am" and hour == 12, do: 0, else: hour
    
    tomorrow = DateTime.utc_now() |> DateTime.add(1, :day)
    %{tomorrow | hour: hour, minute: 0, second: 0, microsecond: {0, 0}} |> DateTime.to_iso8601()
  end
end