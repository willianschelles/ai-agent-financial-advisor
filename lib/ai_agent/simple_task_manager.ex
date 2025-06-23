defmodule AiAgent.SimpleTaskManager do
  @moduledoc """
  Simplified task manager for email->calendar workflows.
  
  This module handles the core task lifecycle:
  1. Create task when user requests email->calendar workflow
  2. Store task state after sending email
  3. Resume task when webhook receives reply
  4. Complete task after creating calendar event
  """
  
  require Logger
  import Ecto.Query
  alias AiAgent.{Repo, Task, User}
  
  @doc """
  Create a task for email->calendar workflow.
  
  ## Example
      create_email_calendar_task(user, "send an email to Bianca asking if she is available tomorrow 4-5pm", %{
        recipient_name: "Bianca Burginski",
        meeting_time: "tomorrow 4-5pm",
        email_sent: false
      })
  """
  def create_email_calendar_task(user, original_request, workflow_data \\ %{}) do
    Logger.info("Creating email->calendar task for user #{user.id}")
    
    attrs = %{
      user_id: user.id,
      title: "Email->Calendar: #{extract_recipient_name(original_request)}",
      status: "pending",
      priority: "medium",
      task_type: "email_calendar_workflow",
      original_request: original_request,
      workflow_state: workflow_data,
      next_step: "send_email"
    }
    
    case %Task{} |> Task.changeset(attrs) |> Repo.insert() do
      {:ok, task} ->
        Logger.info("Created task #{task.id} for email->calendar workflow")
        {:ok, task}
      {:error, changeset} ->
        Logger.error("Failed to create task: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end
  
  @doc """
  Mark task as waiting for email reply after sending email.
  """
  def mark_waiting_for_reply(task_id, email_data) do
    Logger.info("Marking task #{task_id} as waiting for email reply")
    
    case get_task(task_id) do
      {:ok, task} ->
        # Update workflow state with email data
        updated_workflow_state = Map.merge(task.workflow_state, %{
          "email_sent" => true,
          "email_data" => email_data,
          "sent_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })
        
        # Mark as waiting for email reply
        changeset = Task.waiting_changeset(task, "email_reply", %{
          "message_id" => email_data.message_id,
          "thread_id" => email_data.thread_id,
          "recipient_email" => List.first(email_data.to || [])
        })
        |> Task.changeset(%{
          workflow_state: updated_workflow_state,
          next_step: "process_reply"
        })
        
        case Repo.update(changeset) do
          {:ok, updated_task} ->
            Logger.info("Task #{task_id} is now waiting for email reply")
            {:ok, updated_task}
          {:error, changeset} ->
            Logger.error("Failed to mark task as waiting: #{inspect(changeset.errors)}")
            {:error, changeset}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Resume task when email reply is received.
  """
  def resume_task_with_reply(task_id, reply_data) do
    Logger.info("Resuming task #{task_id} with email reply")
    
    case get_task(task_id) do
      {:ok, task} ->
        if Task.waiting?(task) and task.waiting_for == "email_reply" do
          # Update workflow state with reply data
          updated_workflow_state = Map.merge(task.workflow_state, %{
            "reply_received" => true,
            "reply_data" => reply_data,
            "reply_received_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          })
          
          # Resume task
          changeset = Task.resume_changeset(task, "in_progress")
          |> Task.changeset(%{
            workflow_state: updated_workflow_state,
            next_step: "create_calendar_event"
          })
          
          case Repo.update(changeset) do
            {:ok, updated_task} ->
              Logger.info("Task #{task_id} resumed with reply data")
              {:ok, updated_task}
            {:error, changeset} ->
              Logger.error("Failed to resume task: #{inspect(changeset.errors)}")
              {:error, changeset}
          end
        else
          Logger.warning("Task #{task_id} is not waiting for email reply")
          {:error, "Task is not waiting for email reply"}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Complete task after calendar event is created.
  """
  def complete_task_with_calendar(task_id, calendar_data) do
    Logger.info("Completing task #{task_id} with calendar event")
    
    case get_task(task_id) do
      {:ok, task} ->
        # Update workflow state with calendar data
        updated_workflow_state = Map.merge(task.workflow_state, %{
          "calendar_created" => true,
          "calendar_data" => calendar_data,
          "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })
        
        # Mark as completed
        changeset = Task.status_changeset(task, "completed", %{
          workflow_state: updated_workflow_state,
          next_step: nil
        })
        
        case Repo.update(changeset) do
          {:ok, updated_task} ->
            Logger.info("Task #{task_id} completed successfully")
            {:ok, updated_task}
          {:error, changeset} ->
            Logger.error("Failed to complete task: #{inspect(changeset.errors)}")
            {:error, changeset}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Find tasks waiting for email replies that match the incoming email.
  """
  def find_waiting_tasks_for_email(user_id, email_data) do
    Logger.info("Finding waiting tasks for email from user #{user_id}")
    Logger.info("Email data for matching: #{inspect(email_data)}")
    
    query = from(t in Task,
      where: t.user_id == ^user_id,
      where: t.status == "waiting_for_response",
      where: t.waiting_for == "email_reply",
      order_by: [desc: t.inserted_at]
    )
    
    tasks = Repo.all(query)
    Logger.info("Found #{length(tasks)} waiting tasks to check")
    
    # Filter tasks that match the email data with enhanced matching logic
    matching_tasks = Enum.filter(tasks, fn task ->
      Logger.info("Checking task #{task.id} for match...")
      
      waiting_data = task.waiting_for_data || %{}
      Logger.info("  Task waiting data: #{inspect(waiting_data)}")
      
      # Enhanced matching with multiple strategies
      matches = check_all_matching_strategies(waiting_data, email_data, task)
      
      Logger.info("  Matching result: #{matches}")
      matches
    end)
    
    Logger.info("Found #{length(matching_tasks)} matching tasks")
    matching_tasks
  end
  
  defp check_all_matching_strategies(waiting_data, email_data, task) do
    # Strategy 1: Thread ID match (strongest)
    thread_match = check_thread_match(waiting_data, email_data)
    Logger.info("    Thread match: #{thread_match}")
    
    # Strategy 2: Email sender match (check if sender matches our recipient)
    email_match = check_email_sender_match(waiting_data, email_data)
    Logger.info("    Email sender match: #{email_match}")
    
    # Strategy 3: Subject line match (for replies)
    subject_match = check_subject_match(waiting_data, email_data, task)
    Logger.info("    Subject match: #{subject_match}")
    
    # Strategy 4: Recipient name match (fuzzy matching)
    name_match = check_recipient_name_match(waiting_data, email_data, task)
    Logger.info("    Name match: #{name_match}")
    
    # Strategy 5: Recent task match (if this is the most recent task)
    recent_match = check_recent_task_match(email_data, task)
    Logger.info("    Recent task match: #{recent_match}")
    
    # Return true if any strategy matches
    final_match = thread_match or email_match or subject_match or name_match or recent_match
    Logger.info("    Final match decision: #{final_match}")
    
    final_match
  end
  
  defp check_thread_match(waiting_data, email_data) do
    case {Map.get(waiting_data, "thread_id"), Map.get(email_data, :thread_id)} do
      {nil, _} -> false
      {_, nil} -> false
      {waiting_thread, reply_thread} when is_binary(waiting_thread) and is_binary(reply_thread) ->
        waiting_thread == reply_thread
      _ -> false
    end
  end
  
  defp check_email_sender_match(waiting_data, email_data) do
    waiting_recipient = Map.get(waiting_data, "recipient_email")
    reply_sender = Map.get(email_data, :from)
    
    if waiting_recipient && reply_sender do
      # Check if the email sender contains the recipient we sent to
      sender_lower = String.downcase(reply_sender)
      recipient_lower = String.downcase(waiting_recipient)
      
      # Try different matching approaches
      exact_match = sender_lower == recipient_lower
      contains_match = String.contains?(sender_lower, recipient_lower)
      email_extract_match = extract_email_from_string(sender_lower) == extract_email_from_string(recipient_lower)
      
      Logger.info("      Sender: #{reply_sender}")
      Logger.info("      Expected recipient: #{waiting_recipient}")
      Logger.info("      Exact match: #{exact_match}")
      Logger.info("      Contains match: #{contains_match}")
      Logger.info("      Email extract match: #{email_extract_match}")
      
      exact_match or contains_match or email_extract_match
    else
      false
    end
  end
  
  defp check_subject_match(waiting_data, email_data, task) do
    reply_subject = Map.get(email_data, :subject)
    
    if reply_subject do
      subject_lower = String.downcase(reply_subject)
      
      # Check if it's a reply (starts with "Re:")
      is_reply = String.starts_with?(subject_lower, "re:")
      
      # Check if subject contains meeting-related keywords
      contains_meeting_keywords = String.contains?(subject_lower, ["meeting", "available", "schedule", "appointment"])
      
      # Check if subject contains the recipient name from the task
      recipient_name = get_in(task.workflow_state, ["recipient_name"])
      contains_recipient_name = if recipient_name do
        String.contains?(subject_lower, String.downcase(recipient_name))
      else
        false
      end
      
      Logger.info("      Subject: #{reply_subject}")
      Logger.info("      Is reply: #{is_reply}")
      Logger.info("      Contains meeting keywords: #{contains_meeting_keywords}")
      Logger.info("      Contains recipient name: #{contains_recipient_name}")
      
      is_reply and (contains_meeting_keywords or contains_recipient_name)
    else
      false
    end
  end
  
  defp check_recipient_name_match(waiting_data, email_data, task) do
    reply_sender = Map.get(email_data, :from)
    recipient_name = get_in(task.workflow_state, ["recipient_name"])
    
    if reply_sender && recipient_name do
      sender_lower = String.downcase(reply_sender)
      
      # Split recipient name into parts and check if any part appears in sender
      name_parts = String.split(String.downcase(recipient_name), " ")
      |> Enum.filter(&(String.length(&1) > 2))
      
      name_match = Enum.any?(name_parts, fn part ->
        String.contains?(sender_lower, part)
      end)
      
      Logger.info("      Sender: #{reply_sender}")
      Logger.info("      Expected recipient name: #{recipient_name}")
      Logger.info("      Name parts: #{inspect(name_parts)}")
      Logger.info("      Name match: #{name_match}")
      
      name_match
    else
      false
    end
  end
  
  defp check_recent_task_match(email_data, task) do
    # If this task was created recently (within last 24 hours) and no other matches found,
    # it's likely the right task
    task_age_hours = DateTime.diff(DateTime.utc_now(), task.inserted_at, :hour)
    is_recent = task_age_hours <= 24
    
    Logger.info("      Task age: #{task_age_hours} hours")
    Logger.info("      Is recent: #{is_recent}")
    
    # Only use this as a weak signal if the task is very recent
    is_recent and task_age_hours <= 2
  end
  
  defp extract_email_from_string(str) do
    case Regex.run(~r/([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/, str) do
      [_, email] -> String.downcase(email)
      _ -> str
    end
  end
  
  @doc """
  Get task by ID.
  """
  def get_task(task_id) do
    case Repo.get(Task, task_id) do
      nil -> {:error, :not_found}
      task -> {:ok, task}
    end
  end
  
  @doc """
  Get user's active tasks.
  """
  def get_user_active_tasks(user_id) do
    query = from(t in Task,
      where: t.user_id == ^user_id,
      where: t.status in ["pending", "in_progress", "waiting_for_response"],
      order_by: [desc: t.inserted_at]
    )
    
    Repo.all(query)
  end
  
  @doc """
  Fail a task with reason.
  """
  def fail_task(task_id, reason) do
    Logger.error("Failing task #{task_id}: #{reason}")
    
    case get_task(task_id) do
      {:ok, task} ->
        changeset = Task.status_changeset(task, "failed", %{
          failure_reason: reason,
          next_step: nil
        })
        
        case Repo.update(changeset) do
          {:ok, updated_task} ->
            Logger.info("Task #{task_id} marked as failed")
            {:ok, updated_task}
          {:error, changeset} ->
            Logger.error("Failed to mark task as failed: #{inspect(changeset.errors)}")
            {:error, changeset}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  # Private helpers
  
  defp extract_recipient_name(request) do
    # Extract recipient name from request
    patterns = [
      ~r/(?:to|email)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)/i,
      ~r/([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)/
    ]
    
    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, request) do
        [_, name] -> String.trim(name)
        _ -> nil
      end
    end) || "Unknown Recipient"
  end
end