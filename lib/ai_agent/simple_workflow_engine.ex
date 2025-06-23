defmodule AiAgent.SimpleWorkflowEngine do
  @moduledoc """
  Dynamic workflow engine that intelligently handles multi-step processes.

  Instead of rigid patterns, this engine:
  - Analyzes user intent naturally
  - Creates appropriate workflows based on context
  - Adapts to different communication and scheduling needs
  - Uses available information to enhance interactions
  """

  require Logger
  alias AiAgent.{SimpleTaskManager, LLM.ToolCalling}

  @doc """
  Intelligently process user requests that may involve multi-step workflows.
  """
  def handle_email_calendar_request(user, request) do
    Logger.info("Analyzing request for potential workflow: user #{user.id}")

    # Analyze the request to understand user intent
    case analyze_user_intent(request) do
      {:workflow_needed, workflow_type, workflow_data} ->
        Logger.info("Creating #{workflow_type} workflow")

        case SimpleTaskManager.create_email_calendar_task(user, request, workflow_data) do
          {:ok, task} ->
            execute_workflow_step(task, user)

          {:error, reason} ->
            Logger.error("Failed to create workflow task: #{inspect(reason)}")
            {:error, "Failed to create task: #{inspect(reason)}"}
        end

      {:single_action, _action_type} ->
        # This is a single action, not a workflow
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

  defp analyze_user_intent(request) do
    # Use natural language understanding to determine intent
    request_lower = String.downcase(request)

    cond do
      # Multi-step communication workflows
      involves_follow_up_communication?(request_lower) ->
        {:workflow_needed, "communication_follow_up", extract_communication_data(request)}

      # Meeting coordination workflows
      involves_meeting_coordination?(request_lower) ->
        {:workflow_needed, "meeting_coordination", extract_meeting_coordination_data(request)}

      # Information gathering workflows
      involves_information_gathering?(request_lower) ->
        {:workflow_needed, "information_gathering", extract_information_data(request)}

      # Single actions
      true ->
        {:single_action, determine_single_action_type(request_lower)}
    end
  end

  defp involves_follow_up_communication?(request) do
    # Check for patterns that suggest follow-up communication is needed
    communication_patterns = [
      "ask.*and.*schedule",
      "email.*about.*meeting",
      "send.*and.*follow.*up",
      "check.*availability.*and",
      "reach out.*about.*calendar"
    ]

    Enum.any?(communication_patterns, fn pattern ->
      Regex.match?(~r/#{pattern}/i, request)
    end)
  end

  defp involves_meeting_coordination?(request) do
    has_outreach = String.contains?(request, ["email", "contact", "reach out", "send"])
    has_scheduling = String.contains?(request, ["meeting", "schedule", "calendar", "available", "appointment"])

    has_outreach and has_scheduling
  end

  defp involves_information_gathering?(request) do
    String.contains?(request, ["ask about", "inquire about", "get information", "find out"])
  end

  defp determine_single_action_type(request) do
    cond do
      String.contains?(request, ["email", "send", "message"]) -> "email"
      String.contains?(request, ["schedule", "calendar", "meeting"]) -> "calendar"
      String.contains?(request, ["note", "crm", "contact"]) -> "crm"
      true -> "unknown"
    end
  end

  defp extract_communication_data(request) do
    %{
      "recipient" => extract_recipient_info(request),
      "purpose" => extract_communication_purpose(request),
      "context" => extract_context_clues(request),
      "workflow_type" => "communication_follow_up"
    }
  end

  defp extract_meeting_coordination_data(request) do
    %{
      "recipient" => extract_recipient_info(request),
      "meeting_context" => extract_meeting_context(request),
      "timing_preferences" => extract_timing_info(request),
      "workflow_type" => "meeting_coordination"
    }
  end

  defp extract_information_data(request) do
    %{
      "target" => extract_recipient_info(request),
      "information_needed" => extract_information_type(request),
      "workflow_type" => "information_gathering"
    }
  end

  defp extract_recipient_info(request) do
    # More flexible recipient extraction
    cond do
      # Email address pattern
      match = Regex.run(~r/([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/i, request) ->
        %{"email" => List.last(match), "type" => "email"}

      # Name patterns - be more flexible
      match = Regex.run(~r/(?:to|with|email|contact)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)/i, request) ->
        %{"name" => List.last(match), "type" => "name"}

      # Generic patterns
      String.contains?(String.downcase(request), ["the team", "team", "everyone"]) ->
        %{"group" => "team", "type" => "group"}

      String.contains?(String.downcase(request), ["client", "clients"]) ->
        %{"group" => "clients", "type" => "group"}

      true ->
        %{"unknown" => true, "type" => "unknown"}
    end
  end

  defp extract_communication_purpose(request) do
    request_lower = String.downcase(request)

    cond do
      String.contains?(request_lower, ["available", "availability", "free"]) -> "availability_check"
      String.contains?(request_lower, ["follow up", "follow-up", "checking"]) -> "follow_up"
      String.contains?(request_lower, ["meeting", "schedule", "appointment"]) -> "meeting_request"
      String.contains?(request_lower, ["update", "inform", "tell"]) -> "information_sharing"
      true -> "general_communication"
    end
  end

  defp extract_context_clues(request) do
    # Extract contextual information that might be useful
    context = %{}

    context = if String.contains?(String.downcase(request), ["urgent", "asap", "quickly"]) do
      Map.put(context, "urgency", "high")
    else
      context
    end

    context = if String.contains?(String.downcase(request), ["tomorrow", "next week", "monday"]) do
      Map.put(context, "timing_mentioned", true)
    else
      context
    end

    context
  end

  defp extract_meeting_context(request) do
    request_lower = String.downcase(request)

    context = %{"original_request" => request}

    # Extract meeting type
    context = cond do
      String.contains?(request_lower, ["review", "quarterly", "annual"]) ->
        Map.put(context, "meeting_type", "review")

      String.contains?(request_lower, ["planning", "strategy", "plan"]) ->
        Map.put(context, "meeting_type", "planning")

      String.contains?(request_lower, ["discussion", "discuss", "talk"]) ->
        Map.put(context, "meeting_type", "discussion")

      true ->
        Map.put(context, "meeting_type", "general")
    end

    context
  end

  defp extract_timing_info(request) do
    # Extract timing information more flexibly
    timing = %{}

    # Look for specific times
    case Regex.run(~r/(\d+(?::\d+)?[ap]m)/i, request) do
      [_, time] -> Map.put(timing, "specific_time", time)
      _ -> timing
    end
    |> then(fn timing ->
      # Look for day references
      cond do
        String.contains?(String.downcase(request), "tomorrow") ->
          Map.put(timing, "day_reference", "tomorrow")

        String.contains?(String.downcase(request), "next week") ->
          Map.put(timing, "day_reference", "next_week")

        String.contains?(String.downcase(request), "today") ->
          Map.put(timing, "day_reference", "today")

        true -> timing
      end
    end)
  end

  defp extract_information_type(request) do
    request_lower = String.downcase(request)

    cond do
      String.contains?(request_lower, ["portfolio", "investment"]) -> "portfolio_info"
      String.contains?(request_lower, ["market", "performance"]) -> "market_info"
      String.contains?(request_lower, ["meeting", "availability"]) -> "availability_info"
      String.contains?(request_lower, ["contact", "details"]) -> "contact_info"
      true -> "general_info"
    end
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
    Logger.info("Executing intelligent email step for task #{task.id}")

    workflow_state = task.workflow_state
    recipient_info = Map.get(workflow_state, "recipient", %{})

    # Handle different recipient types intelligently
    case get_recipient_contact(user, recipient_info, task.original_request) do
      {:ok, contact_info} ->
        case create_and_send_contextual_email(user, task, contact_info) do
          {:ok, email_result} ->
            # Determine if we need to wait for a reply based on email content
            if should_wait_for_reply?(task, email_result) do
              SimpleTaskManager.mark_waiting_for_reply(task.id, email_result)
              {:ok, %{message: "Email sent, monitoring for reply", email_data: email_result}}
            else
              SimpleTaskManager.complete_task_with_calendar(task.id, %{"email_sent" => true})
              {:ok, %{message: "Email sent successfully", email_data: email_result}}
            end

          {:error, reason} ->
            SimpleTaskManager.fail_task(task.id, "Failed to send email: #{reason}")
            {:error, reason}
        end

      {:error, reason} ->
        SimpleTaskManager.fail_task(task.id, "Contact resolution failed: #{reason}")
        {:error, reason}
    end
  end

  defp get_recipient_contact(user, recipient_info, original_request) do
    case Map.get(recipient_info, "type") do
      "email" ->
        {:ok, %{email: Map.get(recipient_info, "email"), name: "Contact"}}

      "name" ->
        name = Map.get(recipient_info, "name")
        case ToolCalling.execute_tool(user, "email", "email_find_contact", %{
          "name" => name,
          "context_hint" => original_request
        }) do
          {:ok, %{emails_found: [contact | _]}} ->
            {:ok, %{email: contact[:email], name: name}}

          {:ok, %{emails_found: []}} ->
            {:error, "No email found for #{name}"}

          {:error, reason} ->
            {:error, "Contact search failed: #{reason}"}
        end

      "group" ->
        # Handle team/group communications
        handle_group_communication(user, recipient_info, original_request)

      _ ->
        {:error, "Unable to determine recipient contact information"}
    end
  end

  defp handle_group_communication(_user, recipient_info, _original_request) do
    # For now, return an error - this could be enhanced to find team members
    group = Map.get(recipient_info, "group", "unknown")
    {:error, "Group communication (#{group}) not yet implemented"}
  end

  defp should_wait_for_reply?(task, _email_result) do
    # Determine if we should wait for a reply based on the workflow type and context
    workflow_state = task.workflow_state
    workflow_type = Map.get(workflow_state, "workflow_type", "")
    purpose = Map.get(workflow_state, "purpose", "")

    case {workflow_type, purpose} do
      {"meeting_coordination", _} -> true
      {_, "availability_check"} -> true
      {_, "meeting_request"} -> true
      {"information_gathering", _} -> true
      _ -> false
    end
  end

  defp create_and_send_contextual_email(user, task, contact_info) do
    workflow_state = task.workflow_state

    # Generate email content based on workflow context
    email_content = generate_contextual_email_content(task, contact_info, workflow_state)

    # Send the email using the standard email tool
    ToolCalling.execute_tool(user, "email", "email_send", %{
      "to" => [contact_info.email],
      "subject" => email_content.subject,
      "body" => email_content.body
    })
  end

  defp generate_contextual_email_content(task, contact_info, workflow_state) do
    purpose = Map.get(workflow_state, "purpose", "general_communication")
    recipient_name = contact_info.name
    context = Map.get(workflow_state, "context", %{})

    case purpose do
      "availability_check" ->
        generate_availability_email(recipient_name, task, context)

      "meeting_request" ->
        generate_meeting_request_email(recipient_name, task, context)

      "follow_up" ->
        generate_follow_up_email(recipient_name, task, context)

      "information_sharing" ->
        generate_information_email(recipient_name, task, context)

      _ ->
        generate_general_email(recipient_name, task, context)
    end
  end

  defp generate_availability_email(recipient_name, task, context) do
    timing = extract_timing_from_context(task, context)

    %{
      subject: "Meeting Availability - #{timing}",
      body: """
      Hi #{recipient_name},

      I hope this email finds you well.

      I wanted to check if you're available for a meeting #{timing}. Please let me know if this works for your schedule or if you'd prefer a different time.

      Looking forward to hearing from you.

      Best regards
      """
    }
  end

  defp generate_meeting_request_email(recipient_name, task, context) do
    meeting_context = Map.get(task.workflow_state, "meeting_context", %{})
    meeting_type = Map.get(meeting_context, "meeting_type", "discussion")
    timing = extract_timing_from_context(task, context)

    subject = case meeting_type do
      "review" -> "Quarterly Review Meeting Request"
      "planning" -> "Planning Session Request"
      "discussion" -> "Discussion Meeting Request"
      _ -> "Meeting Request"
    end

    %{
      subject: subject,
      body: """
      Hi #{recipient_name},

      I hope you're doing well.

      I'd like to schedule a #{meeting_type} meeting with you #{timing}. Please let me know if this timing works for you, or suggest an alternative that fits your schedule.

      Looking forward to our conversation.

      Best regards
      """
    }
  end

  defp generate_follow_up_email(recipient_name, _task, _context) do
    %{
      subject: "Following Up",
      body: """
      Hi #{recipient_name},

      I wanted to follow up on our previous conversation. Please let me know if you have any questions or if there's anything I can help you with.

      Best regards
      """
    }
  end

  defp generate_information_email(recipient_name, _task, _context) do
    %{
      subject: "Information Request",
      body: """
      Hi #{recipient_name},

      I hope this email finds you well.

      I wanted to reach out to get some information from you. When you have a moment, could you please share the details we discussed?

      Thank you for your time.

      Best regards
      """
    }
  end

  defp generate_general_email(recipient_name, _task, _context) do
    %{
      subject: "Quick Check-in",
      body: """
      Hi #{recipient_name},

      I hope you're doing well.

      I wanted to reach out and connect with you. Please let me know if there's anything I can help you with.

      Best regards
      """
    }
  end

  defp extract_timing_from_context(task, context) do
    # Extract timing information from task and context
    timing_prefs = Map.get(task.workflow_state, "timing_preferences", %{})

    cond do
      Map.has_key?(timing_prefs, "specific_time") ->
        "#{Map.get(timing_prefs, "day_reference", "tomorrow")} at #{timing_prefs["specific_time"]}"

      Map.has_key?(timing_prefs, "day_reference") ->
        timing_prefs["day_reference"]

      Map.get(context, "timing_mentioned") ->
        "at your convenience"

      true ->
        "this week"
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
    Logger.info("Intelligently processing reply for task #{task.id}")

    reply_data = get_in(task.workflow_state, ["reply_data"])
    workflow_type = Map.get(task.workflow_state, "workflow_type", "")

    # Create a natural analysis prompt
    analysis_prompt = create_reply_analysis_prompt(task, reply_data)

    case ToolCalling.ask_with_tools(user, analysis_prompt, %{enable_tools: false, enable_workflows: false}) do
      {:ok, result} ->
        # Process the analysis result more intelligently
        handle_reply_analysis(task, user, result.response, workflow_type)

      {:error, reason} ->
        Logger.error("Failed to analyze reply: #{reason}")
        SimpleTaskManager.fail_task(task.id, "Failed to analyze reply: #{reason}")
        {:error, reason}
    end
  end

  defp create_reply_analysis_prompt(task, reply_data) do
    """
    I received a reply to my #{Map.get(task.workflow_state, "purpose", "communication")}. Please help me understand the response and determine next steps.

    Original request context: #{task.original_request}

    Reply details:
    From: #{Map.get(reply_data, :from, "contact")}
    Subject: #{Map.get(reply_data, :subject, "no subject")}
    Message: #{Map.get(reply_data, :body, "no content")}

    Based on this reply, what should I do next? Consider:
    - Did they agree to meet or provide availability?
    - Did they decline or suggest alternatives?
    - Do they need more information?
    - Is any follow-up action needed?

    Please provide a brief analysis of their response and recommend next steps.
    """
  end

  defp handle_reply_analysis(task, user, analysis_response, workflow_type) do
    response_lower = String.downcase(analysis_response)

    cond do
      # Positive response patterns
      String.contains?(response_lower, ["agree", "accept", "available", "works for me", "sounds good"]) ->
        handle_positive_response(task, user, workflow_type)

      # Negative response patterns
      String.contains?(response_lower, ["decline", "cannot", "not available", "won't work"]) ->
        handle_negative_response(task, analysis_response)

      # Alternative suggestions
      String.contains?(response_lower, ["alternative", "different time", "reschedule", "suggest"]) ->
        handle_alternative_suggestion(task, user, analysis_response)

      # Need more information
      String.contains?(response_lower, ["more information", "details", "question"]) ->
        handle_information_request(task, analysis_response)

      # Default case - unclear response
      true ->
        handle_unclear_response(task, analysis_response)
    end
  end

  defp handle_positive_response(task, user, workflow_type) do
    case workflow_type do
      "meeting_coordination" ->
        Logger.info("Meeting accepted, proceeding to create calendar event")
        execute_workflow_step(%{task | next_step: "create_calendar_event"}, user)

      _ ->
        # Complete task successfully
        SimpleTaskManager.complete_task_with_calendar(task.id, %{
          "response_type" => "positive",
          "completed_successfully" => true
        })
        {:ok, %{message: "Request was accepted, task completed successfully"}}
    end
  end

  defp handle_negative_response(task, analysis_response) do
    SimpleTaskManager.complete_task_with_calendar(task.id, %{
      "response_type" => "negative",
      "reason" => "Request declined",
      "analysis" => analysis_response
    })
    {:ok, %{message: "Request was declined, task completed"}}
  end

  defp handle_alternative_suggestion(task, _user, analysis_response) do
    # For now, complete the task with the alternative suggestion noted
    # In the future, this could trigger a new workflow to handle the alternative
    SimpleTaskManager.complete_task_with_calendar(task.id, %{
      "response_type" => "alternative_suggested",
      "suggestion" => analysis_response,
      "needs_follow_up" => true
    })
    {:ok, %{message: "Alternative suggested, manual follow-up may be needed", suggestion: analysis_response}}
  end

  defp handle_information_request(task, analysis_response) do
    SimpleTaskManager.complete_task_with_calendar(task.id, %{
      "response_type" => "information_requested",
      "details_needed" => analysis_response,
      "needs_follow_up" => true
    })
    {:ok, %{message: "More information requested, follow-up needed", details: analysis_response}}
  end

  defp handle_unclear_response(task, analysis_response) do
    SimpleTaskManager.complete_task_with_calendar(task.id, %{
      "response_type" => "unclear",
      "analysis" => analysis_response,
      "needs_manual_review" => true
    })
    {:ok, %{message: "Response unclear, may need manual review", analysis: analysis_response}}
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
