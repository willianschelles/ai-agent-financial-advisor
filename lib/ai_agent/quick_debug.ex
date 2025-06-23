defmodule AiAgent.QuickDebug do
  @moduledoc """
  Quick debugging functions to check the current state and test webhook matching.
  """
  
  require Logger
  import Ecto.Query
  alias AiAgent.SimpleTaskManager
  
  @doc """
  Show what tasks are currently waiting for user.
  """
  def show_waiting_tasks(user_id) do
    Logger.info("=== WAITING TASKS FOR USER #{user_id} ===")
    
    # Get all waiting tasks
    query = from(t in AiAgent.Task,
      where: t.user_id == ^user_id,
      where: t.status == "waiting_for_response",
      where: t.waiting_for == "email_reply",
      order_by: [desc: t.inserted_at]
    )
    
    tasks = AiAgent.Repo.all(query)
    
    Logger.info("Found #{length(tasks)} tasks waiting for email reply")
    
    Enum.each(tasks, fn task ->
      Logger.info("📧 Task #{task.id}:")
      Logger.info("   Title: #{task.title}")
      Logger.info("   Created: #{task.inserted_at}")
      Logger.info("   Waiting data: #{inspect(task.waiting_for_data)}")
      Logger.info("   Recipient name: #{get_in(task.workflow_state, ["recipient_name"])}")
      Logger.info("   ---")
    end)
    
    tasks
  end
  
  @doc """
  Test webhook matching with fake Bianca data.
  """
  def test_bianca_match(user_id) do
    Logger.info("=== TESTING BIANCA EMAIL MATCH ===")
    
    # Create fake email data that simulates Bianca's reply
    fake_email_data = %{
      from: "Bianca Burginski <bianca.burginski@example.com>",
      subject: "Re: Meeting Request - tomorrow 4-5pm",
      body: "Hi! Yes, I'm available tomorrow from 4-5pm. Looking forward to meeting with you!",
      thread_id: "thread_12345",
      message_id: "msg_67890"
    }
    
    Logger.info("Testing with fake Bianca email:")
    Logger.info("#{inspect(fake_email_data)}")
    
    # Test the matching
    matching_tasks = SimpleTaskManager.find_waiting_tasks_for_email(user_id, fake_email_data)
    
    Logger.info("✅ Result: Found #{length(matching_tasks)} matching tasks")
    
    matching_tasks
  end
  
  @doc """
  Simulate the exact webhook you received and test matching.
  """
  def simulate_real_webhook(user_id \\ 1) do
    Logger.info("=== SIMULATING REAL WEBHOOK ===")
    
    # Create the webhook data in the exact format Gmail sends
    webhook_data = %{
      "message" => %{
        "data" => Base.encode64(Jason.encode!(%{
          "emailAddress" => "willianschelles@gmail.com",
          "historyId" => 91604512
        }))
      }
    }
    
    Logger.info("Webhook data: #{inspect(webhook_data)}")
    
    # Test parsing
    case AiAgent.SimpleWebhookHandler.parse_gmail_webhook(webhook_data) do
      {:ok, parsed_data} ->
        Logger.info("✅ Webhook parsed successfully")
        Logger.info("Parsed data: #{inspect(parsed_data)}")
        
        # For testing, let's manually add some email details since Gmail API might not work
        enhanced_data = Map.merge(parsed_data, %{
          from: "Bianca Burginski <bianca.burginski@example.com>",
          subject: "Re: Meeting Request",
          body: "Yes, I'm available tomorrow!",
          thread_id: "thread_test_123"
        })
        
        Logger.info("Enhanced data for testing: #{inspect(enhanced_data)}")
        
        # Test matching
        matching_tasks = SimpleTaskManager.find_waiting_tasks_for_email(user_id, enhanced_data)
        
        Logger.info("✅ Found #{length(matching_tasks)} matching tasks")
        
        if length(matching_tasks) > 0 do
          Logger.info("🎉 SUCCESS! Tasks would be resumed.")
        else
          Logger.warning("⚠️ No tasks matched. Check the logs above for details.")
        end
        
        matching_tasks
        
      {:error, reason} ->
        Logger.error("❌ Webhook parsing failed: #{reason}")
        []
    end
  end
  
  @doc """
  Create a test waiting task for debugging.
  """
  def create_test_task(user_id) do
    Logger.info("=== CREATING TEST TASK ===")
    
    case AiAgent.Repo.get(AiAgent.User, user_id) do
      nil ->
        Logger.error("❌ User #{user_id} not found")
        {:error, "User not found"}
        
      user ->
        case SimpleTaskManager.create_email_calendar_task(
          user,
          "send an email to Bianca Burginski asking if she is available tomorrow 4-5pm",
          %{
            "recipient_name" => "Bianca Burginski",
            "meeting_details" => %{"time_mentioned" => "tomorrow 4-5pm"}
          }
        ) do
          {:ok, task} ->
            Logger.info("✅ Created task #{task.id}")
            
            # Mark it as waiting for reply
            email_data = %{
              message_id: "test_msg_123",
              thread_id: "test_thread_456",
              to: ["bianca.burginski@example.com"]
            }
            
            case SimpleTaskManager.mark_waiting_for_reply(task.id, email_data) do
              {:ok, updated_task} ->
                Logger.info("✅ Task marked as waiting for reply")
                {:ok, updated_task}
                
              {:error, reason} ->
                Logger.error("❌ Failed to mark as waiting: #{reason}")
                {:error, reason}
            end
            
          {:error, reason} ->
            Logger.error("❌ Failed to create task: #{reason}")
            {:error, reason}
        end
    end
  end
end