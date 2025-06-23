#!/usr/bin/env elixir

# Debug script to analyze the Avenue Connections request
IO.puts("=== Avenue Connections Request Analysis ===")

# Simulate the is_complex_request? logic
defmodule DebugComplexRequest do
  def is_complex_request?(question) do
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
      {false, "analysis_prompt"}
    else
      # Check for common search+email pattern first - handle this as a simple request with tools
      search_and_email_pattern = Regex.match?(~r/search\s+.+\s+and\s+send\s+.+@.+/i, question_lower)
      
      if search_and_email_pattern do
        # This is a search+email request - handle it as simple with tools enabled
        {false, "search_and_email_pattern"}
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
          {true, "multi_step"}  # Complex requests need workflows
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
          {is_action_request, "action_request"}
        end
      end
    end
  end
end

# Test the request
test_request = "search for Avenue Connections info and send to willianschelles@gmail.com"
IO.puts("Request: #{test_request}")

{is_complex, reason} = DebugComplexRequest.is_complex_request?(test_request)
IO.puts("Is Complex Request: #{is_complex}")
IO.puts("Reason: #{reason}")

# Check each multi-step indicator
multi_step_indicators = [
  " and ", " then ", " after ", " following ", " once ", " when ",
  " if ", " unless ", " provided ", " assuming ",
  "schedule.*send", "send.*schedule", "create.*notify", "notify.*create",
  "wait for", "follow up", "remind me", "check back",
  "if.*accepts", "if.*confirms", "if.*agrees", "if.*available"
]

IO.puts("\n=== Multi-Step Indicator Analysis ===")
request_lower = String.downcase(test_request)

Enum.each(multi_step_indicators, fn indicator ->
  match = if String.contains?(indicator, "*") do
    regex_pattern = String.replace(indicator, "*", ".*")
    Regex.match?(~r/#{regex_pattern}/i, request_lower)
  else
    String.contains?(request_lower, indicator)
  end
  
  if match do
    IO.puts("✓ Matched: '#{indicator}'")
  end
end)

# Check action patterns
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

IO.puts("\n=== Action Pattern Analysis ===")
Enum.each(action_patterns, fn pattern ->
  if Regex.match?(pattern, request_lower) do
    IO.puts("✓ Matched action pattern: #{inspect(pattern)}")
  end
end)

IO.puts("\n=== Analysis Summary ===")
IO.puts("The request '#{test_request}' contains:")
IO.puts("- 'and' keyword: #{String.contains?(request_lower, " and ")}")
IO.puts("- 'search' at start: #{String.starts_with?(request_lower, "search")}")
IO.puts("- 'send' keyword: #{String.contains?(request_lower, "send")}")
IO.puts("- Email pattern: #{String.contains?(request_lower, "@")}")

# Test the search+email pattern
search_and_email_pattern = Regex.match?(~r/search\s+.+\s+and\s+send\s+.+@.+/i, request_lower)
IO.puts("- Search+email pattern: #{search_and_email_pattern}")

IO.puts("\nNEW BEHAVIOR: The request should now be classified as SIMPLE because:")
IO.puts("1. It matches the search+email pattern: 'search ... and send ...@...'")
IO.puts("2. This bypasses complex workflow and uses simple tool execution")
IO.puts("3. Tools will be executed directly: search context → send email")
IO.puts("4. This should provide better performance and more reliable execution")