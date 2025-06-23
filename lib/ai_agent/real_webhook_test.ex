defmodule AiAgent.RealWebhookTest do
  @moduledoc """
  Test module for real Gmail webhook processing.
  
  This tests the system with the actual webhook format you're receiving:
  %{"emailAddress" => "willianschelles@gmail.com", "historyId" => 91604512}
  """
  
  require Logger
  alias AiAgent.SimpleWebhookHandler
  
  @doc """
  Test with the exact webhook format you're receiving from Gmail.
  """
  def test_real_webhook_format(user_id \\ 1) do
    Logger.info("=== Testing Real Gmail Webhook Format ===")
    
    # This is the exact format you showed me
    real_webhook_data = %{
      "message" => %{
        "data" => Base.encode64(Jason.encode!(%{
          "emailAddress" => "willianschelles@gmail.com", 
          "historyId" => 91604512
        }))
      }
    }
    
    Logger.info("Webhook data: #{inspect(real_webhook_data)}")
    
    case SimpleWebhookHandler.handle_gmail_webhook(real_webhook_data, user_id) do
      {:ok, results} ->
        Logger.info("✅ Real webhook processed successfully!")
        Logger.info("Results: #{inspect(results)}")
        {:ok, results}
      
      {:error, reason} ->
        Logger.error("❌ Real webhook processing failed: #{reason}")
        {:error, reason}
    end
  end
  
  @doc """
  Test the webhook parsing specifically.
  """
  def test_webhook_parsing() do
    Logger.info("=== Testing Webhook Parsing ===")
    
    real_webhook_data = %{
      "message" => %{
        "data" => Base.encode64(Jason.encode!(%{
          "emailAddress" => "willianschelles@gmail.com", 
          "historyId" => 91604512
        }))
      }
    }
    
    case SimpleWebhookHandler.parse_gmail_webhook(real_webhook_data) do
      {:ok, parsed_data} ->
        Logger.info("✅ Webhook parsed successfully!")
        Logger.info("Parsed data: #{inspect(parsed_data)}")
        {:ok, parsed_data}
      
      {:error, reason} ->
        Logger.error("❌ Webhook parsing failed: #{reason}")
        {:error, reason}
    end
  end
  
  @doc """
  Test the complete flow with a real-format webhook.
  """
  def test_complete_real_flow(user_id \\ 1) do
    Logger.info("=== Testing Complete Real Webhook Flow ===")
    
    # Step 1: Verify user exists
    case AiAgent.Repo.get(AiAgent.User, user_id) do
      nil ->
        Logger.error("❌ User #{user_id} not found")
        {:error, "User not found"}
      
      user ->
        Logger.info("✅ User found: #{user.email}")
        
        # Step 2: Create a waiting task first
        case create_test_waiting_task(user) do
          {:ok, task} ->
            Logger.info("✅ Created test waiting task: #{task.id}")
            
            # Step 3: Simulate the real webhook
            real_webhook_data = %{
              "message" => %{
                "data" => Base.encode64(Jason.encode!(%{
                  "emailAddress" => user.email,  # Use the actual user's email
                  "historyId" => 91604512
                }))
              }
            }
            
            # Step 4: Process the webhook
            case SimpleWebhookHandler.handle_gmail_webhook(real_webhook_data, user_id) do
              {:ok, results} ->
                Logger.info("✅ Complete real flow successful!")
                Logger.info("Results: #{inspect(results)}")
                {:ok, %{task: task, webhook_results: results}}
              
              {:error, reason} ->
                Logger.error("❌ Webhook processing failed: #{reason}")
                {:error, reason}
            end
          
          {:error, reason} ->
            Logger.error("❌ Failed to create test task: #{reason}")
            {:error, reason}
        end
    end
  end
  
  defp create_test_waiting_task(user) do
    # Create a task that's waiting for email reply
    case AiAgent.SimpleTaskManager.create_email_calendar_task(
      user, 
      "send an email to Bianca Burginski asking if she is available tomorrow 4-5pm",
      %{
        "recipient_name" => "Bianca Burginski",
        "meeting_details" => %{"time_mentioned" => "tomorrow 4-5pm"}
      }
    ) do
      {:ok, task} ->
        # Mark it as waiting for reply with some mock email data
        email_data = %{
          message_id: "test_msg_123",
          thread_id: "test_thread_456",
          to: ["bianca.burginski@example.com"]
        }
        
        AiAgent.SimpleTaskManager.mark_waiting_for_reply(task.id, email_data)
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Show what the current system expects vs what Gmail sends.
  """
  def show_format_comparison() do
    Logger.info("=== Gmail Webhook Format Comparison ===")
    
    Logger.info("What Gmail actually sends:")
    gmail_actual = %{
      "message" => %{
        "data" => Base.encode64(Jason.encode!(%{
          "emailAddress" => "willianschelles@gmail.com", 
          "historyId" => 91604512
        }))
      }
    }
    Logger.info("#{inspect(gmail_actual, pretty: true)}")
    
    Logger.info("\nWhat our system was expecting (old format):")
    old_expected = %{
      "message_id" => "msg_123",
      "thread_id" => "thread_456",
      "from" => "sender@example.com",
      "subject" => "Re: Meeting Request",
      "body" => "Yes, I'm available!"
    }
    Logger.info("#{inspect(old_expected, pretty: true)}")
    
    Logger.info("\nNow our system will:")
    Logger.info("1. Parse the Gmail webhook to get emailAddress and historyId")
    Logger.info("2. Use historyId to fetch new messages via Gmail API")
    Logger.info("3. Get full message details including from, subject, body")
    Logger.info("4. Process as before with real email data")
    
    :ok
  end
end