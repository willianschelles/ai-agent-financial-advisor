defmodule AiAgent.LLM.TestRequestDetection do
  @moduledoc """
  Test module to verify request complexity detection works correctly.
  """

  require Logger

  @doc """
  Test the is_complex_request? function with various inputs.
  """
  def test_request_detection() do
    Logger.info("=== Testing Request Complexity Detection ===")

    # Simple informational questions that should NOT be complex
    simple_questions = [
      "What is the Avenua Connections?",
      "Who mentioned baseball?",
      "What deals are closing this month?",
      "Show me emails from last week",
      "What's my calendar for tomorrow?",
      "Who are my HubSpot contacts?",
      "What is the status of the TechCorp deal?",
      "How many meetings do I have today?",
      "What's the latest email from John?"
    ]

    # Complex requests that SHOULD be complex
    complex_requests = [
      "Send an email to John and schedule a meeting for tomorrow",
      "Schedule a meeting with Sarah and then send her the agenda",
      "Send an email to the prospect and wait for their reply",
      "Email John about the meeting and if he accepts, create a calendar event",
      "Schedule a meeting with the team and send follow-up emails after",
      "Create a HubSpot contact and send them a welcome email"
    ]

    # Action requests that should be complex (require tools)
    action_requests = [
      "Send an email to john@example.com",
      "Schedule a meeting with Sarah tomorrow at 2pm", 
      "Add John Doe to HubSpot",
      "Create a calendar event for next week",
      "Update the TechCorp contact in HubSpot"
    ]

    Logger.info("Testing simple questions (should be FALSE):")
    test_questions(simple_questions, false)

    Logger.info("\nTesting complex requests (should be TRUE):")
    test_questions(complex_requests, true)

    Logger.info("\nTesting action requests (should be TRUE):")
    test_questions(action_requests, true)
  end

  defp test_questions(questions, expected_result) do
    questions
    |> Enum.with_index()
    |> Enum.each(fn {question, index} ->
      result = is_complex_request?(question)
      status = if result == expected_result, do: "✅", else: "❌"
      
      Logger.info("#{index + 1}. #{status} \"#{question}\" -> #{result}")
      
      if result != expected_result do
        Logger.error("   Expected: #{expected_result}, Got: #{result}")
      end
    end)
  end

  # Copy the actual function from ToolCalling for testing
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
        true  # Complex requests need workflows
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