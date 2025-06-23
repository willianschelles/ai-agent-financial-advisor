defmodule AiAgent.WebhookDebug do
  @moduledoc """
  Debug tools to understand why webhook task matching isn't working.
  """
  
  require Logger
  alias AiAgent.SimpleTaskManager
  
  @doc """
  Debug the complete webhook flow to see where it's failing.
  """
  def debug_webhook_flow(user_id, webhook_data) do
    Logger.info("=== DEBUGGING WEBHOOK FLOW ===")
    
    # Step 1: Check user and waiting tasks
    debug_user_and_tasks(user_id)
    
    # Step 2: Debug webhook parsing
    debug_webhook_parsing(webhook_data)
    
    # Step 3: Debug task matching logic
    debug_task_matching(user_id, webhook_data)
    
    :ok
  end
  
  def debug_user_and_tasks(user_id) do
    Logger.info("--- Step 1: User and Tasks Debug ---")
    
    case AiAgent.Repo.get(AiAgent.User, user_id) do
      nil ->
        Logger.error("❌ User #{user_id} not found!")
        
      user ->
        Logger.info("✅ User found: #{user.email}")
        
        # Check all user tasks
        all_tasks = SimpleTaskManager.get_user_active_tasks(user_id)
        Logger.info("📋 Total active tasks: #{length(all_tasks)}")
        
        # Check waiting tasks specifically
        waiting_tasks = Enum.filter(all_tasks, fn task -> 
          task.status == "waiting_for_response" and task.waiting_for == "email_reply"
        end)
        Logger.info("⏳ Tasks waiting for email reply: #{length(waiting_tasks)}")
        
        # Show details of waiting tasks
        Enum.each(waiting_tasks, fn task ->
          Logger.info("📧 Task #{task.id}:")
          Logger.info("   Status: #{task.status}")
          Logger.info("   Waiting for: #{task.waiting_for}")
          Logger.info("   Title: #{task.title}")
          Logger.info("   Waiting data: #{inspect(task.waiting_for_data)}")
          Logger.info("   Workflow state keys: #{inspect(Map.keys(task.workflow_state || %{}))}")
        end)
    end
  end
  
  def debug_webhook_parsing(webhook_data) do
    Logger.info("--- Step 2: Webhook Parsing Debug ---")
    
    Logger.info("🔗 Received webhook data: #{inspect(webhook_data)}")
    
    case AiAgent.SimpleWebhookHandler.parse_gmail_webhook(webhook_data) do
      {:ok, parsed_data} ->
        Logger.info("✅ Webhook parsed successfully")
        Logger.info("📧 Parsed email data: #{inspect(parsed_data)}")
        
      {:error, reason} ->
        Logger.error("❌ Webhook parsing failed: #{reason}")
    end
  end
  
  def debug_task_matching(user_id, webhook_data) do
    Logger.info("--- Step 3: Task Matching Debug ---")
    
    # Simulate the email data that would be extracted
    case AiAgent.SimpleWebhookHandler.parse_gmail_webhook(webhook_data) do
      {:ok, email_data} ->
        # Try to enhance the email data (this is where Gmail API calls happen)
        enhanced_data = debug_email_enhancement(email_data, webhook_data, user_id)
        
        # Now test the task matching
        debug_find_matching_tasks(user_id, enhanced_data)
        
      {:error, reason} ->
        Logger.error("❌ Cannot test task matching - webhook parsing failed: #{reason}")
    end
  end
  
  def debug_email_enhancement(email_data, webhook_data, user_id) do
    Logger.info("🔍 Testing email data enhancement...")
    
    case AiAgent.Repo.get(AiAgent.User, user_id) do
      nil ->
        Logger.error("❌ User not found for enhancement")
        email_data
        
      user ->
        # Try to enhance with Gmail API
        history_id = Map.get(email_data, :history_id)
        
        if history_id do
          Logger.info("📈 Attempting to fetch Gmail history with ID: #{history_id}")
          
          case AiAgent.Google.GmailAPI.get_history(user, history_id, %{historyTypes: ["messageAdded"]}) do
            {:ok, history_response} ->
              Logger.info("✅ Gmail history fetched successfully")
              Logger.info("📊 History response keys: #{inspect(Map.keys(history_response))}")
              
              # Check for new messages
              case Map.get(history_response, "history") do
                nil ->
                  Logger.warn("⚠️ No 'history' key in response")
                  email_data
                  
                history_items when is_list(history_items) ->
                  Logger.info("📬 Found #{length(history_items)} history items")
                  
                  messages = history_items
                  |> Enum.flat_map(fn item ->
                    Map.get(item, "messagesAdded", [])
                  end)
                  |> Enum.map(fn item ->
                    Map.get(item, "message")
                  end)
                  |> Enum.reject(&is_nil/1)
                  
                  Logger.info("📨 Found #{length(messages)} new messages")
                  
                  if length(messages) > 0 do
                    latest_message = List.first(messages)
                    message_id = latest_message["id"]
                    Logger.info("🎯 Latest message ID: #{message_id}")
                    
                    # Try to get message details
                    debug_message_details(user, message_id, email_data)
                  else
                    Logger.warn("⚠️ No new messages in history")
                    email_data
                  end
                  
                _ ->
                  Logger.warn("⚠️ History is not a list: #{inspect(Map.get(history_response, "history"))}")
                  email_data
              end
              
            {:error, reason} ->
              Logger.error("❌ Gmail history fetch failed: #{reason}")
              # For debugging, let's create some mock enhanced data
              Logger.info("🔧 Creating mock enhanced data for testing...")
              Map.merge(email_data, %{
                from: "bianca.burginski@example.com",
                subject: "Re: Meeting Request",
                body: "Yes, I'm available tomorrow from 4-5pm!",
                thread_id: "mock_thread_123"
              })
          end
        else
          Logger.warn("⚠️ No history_id in email data")
          email_data
        end
    end
  end
  
  def debug_message_details(user, message_id, email_data) do
    Logger.info("📧 Fetching details for message: #{message_id}")
    
    case AiAgent.Google.GmailAPI.get_message(user, message_id) do
      {:ok, message} ->
        Logger.info("✅ Message details fetched")
        
        headers = get_in(message, ["payload", "headers"]) || []
        labels = Map.get(message, "labelIds", [])
        
        from = extract_header_value(headers, "From")
        subject = extract_header_value(headers, "Subject")
        thread_id = message["threadId"]
        
        Logger.info("📧 Message details:")
        Logger.info("   From: #{from}")
        Logger.info("   Subject: #{subject}")
        Logger.info("   Thread ID: #{thread_id}")
        Logger.info("   Labels: #{inspect(labels)}")
        
        # Check if it's incoming
        is_incoming = "INBOX" in labels and "SENT" not in labels
        Logger.info("   Is incoming: #{is_incoming}")
        
        if is_incoming do
          Map.merge(email_data, %{
            message_id: message["id"],
            thread_id: thread_id,
            from: from,
            subject: subject,
            labels: labels
          })
        else
          Logger.warn("⚠️ Message is not incoming, skipping")
          email_data
        end
        
      {:error, reason} ->
        Logger.error("❌ Failed to get message details: #{reason}")
        email_data
    end
  end
  
  def debug_find_matching_tasks(user_id, email_data) do
    Logger.info("🔍 Testing task matching with email data:")
    Logger.info("#{inspect(email_data)}")
    
    # Use the actual matching logic from SimpleTaskManager
    matching_tasks = SimpleTaskManager.find_waiting_tasks_for_email(user_id, email_data)
    
    Logger.info("🎯 Found #{length(matching_tasks)} matching tasks")
    
    if length(matching_tasks) == 0 do
      Logger.warn("⚠️ No matching tasks found! Let's debug why...")
      debug_why_no_matches(user_id, email_data)
    else
      Enum.each(matching_tasks, fn task ->
        Logger.info("✅ Matching task: #{task.id} - #{task.title}")
      end)
    end
  end
  
  def debug_why_no_matches(user_id, email_data) do
    Logger.info("🔍 Debugging why no tasks matched...")
    
    # Get all waiting tasks
    all_waiting = SimpleTaskManager.get_user_active_tasks(user_id)
    |> Enum.filter(fn task ->
      task.status == "waiting_for_response" and task.waiting_for == "email_reply"
    end)
    
    Logger.info("📋 All waiting tasks: #{length(all_waiting)}")
    
    Enum.each(all_waiting, fn task ->
      Logger.info("🔍 Checking task #{task.id}:")
      Logger.info("   Waiting data: #{inspect(task.waiting_for_data)}")
      
      waiting_data = task.waiting_for_data || %{}
      
      # Check thread matching
      waiting_thread = Map.get(waiting_data, "thread_id")
      email_thread = Map.get(email_data, :thread_id)
      thread_match = waiting_thread && email_thread && waiting_thread == email_thread
      
      Logger.info("   Thread match: #{thread_match} (waiting: #{waiting_thread}, email: #{email_thread})")
      
      # Check email matching
      waiting_recipient = Map.get(waiting_data, "recipient_email")
      email_sender = Map.get(email_data, :from)
      
      email_match = if waiting_recipient && email_sender do
        String.contains?(String.downcase(email_sender), String.downcase(waiting_recipient))
      else
        false
      end
      
      Logger.info("   Email match: #{email_match} (waiting: #{waiting_recipient}, sender: #{email_sender})")
      
      overall_match = thread_match or email_match
      Logger.info("   Overall match: #{overall_match}")
    end)
  end
  
  defp extract_header_value(headers, header_name) do
    case Enum.find(headers, fn h -> h["name"] == header_name end) do
      nil -> nil
      header -> header["value"]
    end
  end
  
  @doc """
  Quick test to see current state of tasks.
  """
  def show_current_tasks(user_id) do
    Logger.info("=== CURRENT TASKS FOR USER #{user_id} ===")
    
    tasks = SimpleTaskManager.get_user_active_tasks(user_id)
    
    Logger.info("📋 Total active tasks: #{length(tasks)}")
    
    Enum.each(tasks, fn task ->
      Logger.info("📋 Task #{task.id}:")
      Logger.info("   Title: #{task.title}")
      Logger.info("   Status: #{task.status}")
      Logger.info("   Type: #{task.task_type}")
      Logger.info("   Waiting for: #{task.waiting_for}")
      Logger.info("   Next step: #{task.next_step}")
      Logger.info("   Created: #{task.inserted_at}")
      Logger.info("   ---")
    end)
  end
end