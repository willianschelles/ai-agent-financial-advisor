defmodule AiAgent.EmailCalendarFlowTest do
  @moduledoc """
  Test module for the complete email->calendar workflow.
  
  This tests the full flow:
  1. User request: "send email to Bianca asking about meeting"
  2. System sends email and creates waiting task
  3. Webhook receives reply
  4. System creates calendar event
  """
  
  require Logger
  alias AiAgent.{SimpleWorkflowEngine, SimpleWebhookHandler, SimpleTaskManager}
  alias AiAgent.LLM.ToolCalling
  
  @doc """
  Test the complete email->calendar workflow end-to-end.
  
  ## Parameters
  - user: User struct
  - request: User request like "send email to Bianca asking if available tomorrow 4-5pm"
  
  ## Returns
  - {:ok, result} with the complete flow results
  - {:error, reason} if the flow failed
  """
  def test_complete_flow(user, request \\ "send an email to Bianca Burginski asking if she is available tomorrow 4-5pm") do
    Logger.info("=== Testing Complete Email->Calendar Flow ===")
    Logger.info("User: #{user.id}")
    Logger.info("Request: #{request}")
    
    step_1_result = test_step_1_email_sending(user, request)
    
    case step_1_result do
      {:ok, step_1_data} ->
        # Simulate some time passing
        :timer.sleep(1000)
        
        step_2_result = test_step_2_webhook_processing(user.id, step_1_data)
        
        case step_2_result do
          {:ok, step_2_data} ->
            {:ok, %{
              step_1: step_1_data,
              step_2: step_2_data,
              message: "Complete email->calendar flow test successful!"
            }}
          
          {:error, reason} ->
            {:error, "Step 2 (webhook) failed: #{reason}"}
        end
      
      {:error, reason} ->
        {:error, "Step 1 (email) failed: #{reason}"}
    end
  end
  
  @doc """
  Test Step 1: Email sending and task creation.
  """
  def test_step_1_email_sending(user, request) do
    Logger.info("--- Step 1: Testing Email Sending ---")
    
    case ToolCalling.ask_with_tools(user, request) do
      {:ok, result} ->
        Logger.info("Step 1 successful!")
        Logger.info("Response: #{result.response}")
        Logger.info("Waiting: #{Map.get(result, :waiting, false)}")
        Logger.info("Metadata: #{inspect(Map.get(result, :metadata, %{}))}")
        
        # Check if we have active tasks
        active_tasks = SimpleTaskManager.get_user_active_tasks(user.id)
        Logger.info("Active tasks after step 1: #{length(active_tasks)}")
        
        if length(active_tasks) > 0 do
          task = List.first(active_tasks)
          Logger.info("Latest task: #{task.id} - Status: #{task.status} - Waiting for: #{task.waiting_for}")
          
          {:ok, %{
            tool_calling_result: result,
            task: task,
            active_tasks_count: length(active_tasks)
          }}
        else
          {:error, "No active tasks created"}
        end
      
      {:error, reason} ->
        Logger.error("Step 1 failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Test Step 2: Webhook processing and calendar creation.
  """
  def test_step_2_webhook_processing(user_id, step_1_data) do
    Logger.info("--- Step 2: Testing Webhook Processing ---")
    
    # Create a mock email reply
    mock_reply = %{
      message_id: "reply_#{:rand.uniform(1000000)}",
      thread_id: "thread_#{:rand.uniform(100000)}",
      from: "bianca.burginski@example.com",
      subject: "Re: Meeting Request",
      body: "Yes, I'm available tomorrow from 4-5pm. Looking forward to meeting with you!"
    }
    
    Logger.info("Simulating email reply: #{inspect(mock_reply)}")
    
    case SimpleWebhookHandler.simulate_email_reply(user_id, mock_reply) do
      {:ok, results} ->
        Logger.info("Step 2 successful!")
        Logger.info("Webhook processing results: #{inspect(results)}")
        
        # Check task status after webhook
        active_tasks = SimpleTaskManager.get_user_active_tasks(user_id)
        Logger.info("Active tasks after step 2: #{length(active_tasks)}")
        
        # Check if any tasks were completed
        all_user_tasks = SimpleTaskManager.get_user_active_tasks(user_id)
        completed_tasks = Enum.filter(all_user_tasks, fn task -> task.status == "completed" end)
        Logger.info("Completed tasks: #{length(completed_tasks)}")
        
        {:ok, %{
          webhook_results: results,
          mock_reply: mock_reply,
          active_tasks_after: length(active_tasks),
          completed_tasks: length(completed_tasks)
        }}
      
      {:error, reason} ->
        Logger.error("Step 2 failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Test just the workflow engine detection.
  """
  def test_workflow_detection(user, request) do
    Logger.info("=== Testing Workflow Detection ===")
    
    case SimpleWorkflowEngine.handle_email_calendar_request(user, request) do
      {:ok, result} ->
        Logger.info("Detected as email->calendar workflow")
        Logger.info("Result: #{inspect(result)}")
        {:ok, result}
      
      {:not_email_calendar_workflow, _} ->
        Logger.info("Not detected as email->calendar workflow")
        {:not_workflow, request}
      
      {:error, reason} ->
        Logger.error("Workflow detection failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Reset test data - clean up any tasks for the user.
  """
  def reset_test_data(user_id) do
    Logger.info("=== Resetting Test Data ===")
    
    # Get all user tasks and cancel them
    active_tasks = SimpleTaskManager.get_user_active_tasks(user_id)
    
    Enum.each(active_tasks, fn task ->
      case AiAgent.TaskManager.cancel_task(task.id, "Test cleanup") do
        {:ok, _} -> Logger.info("Cancelled task #{task.id}")
        {:error, reason} -> Logger.warn("Failed to cancel task #{task.id}: #{reason}")
      end
    end)
    
    Logger.info("Reset complete. Cancelled #{length(active_tasks)} tasks.")
    :ok
  end
  
  @doc """
  Get test status - show current tasks and their states.
  """
  def get_test_status(user_id) do
    Logger.info("=== Test Status ===")
    
    active_tasks = SimpleTaskManager.get_user_active_tasks(user_id)
    
    Logger.info("Active tasks: #{length(active_tasks)}")
    
    Enum.each(active_tasks, fn task ->
      Logger.info("Task #{task.id}: #{task.status} - #{task.task_type} - Waiting for: #{task.waiting_for}")
      Logger.info("  Title: #{task.title}")
      Logger.info("  Next step: #{task.next_step}")
      Logger.info("  Workflow state keys: #{Map.keys(task.workflow_state || %{})}")
    end)
    
    %{
      active_tasks_count: length(active_tasks),
      tasks: active_tasks
    }
  end
end