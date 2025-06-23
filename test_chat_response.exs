#!/usr/bin/env elixir

# Test script to verify chat response flow is working
Mix.install([
  {:req, "~> 0.3"}
])

# Test our request detection function directly
require Logger

# Load our app modules
Code.require_file("lib/ai_agent/llm/tool_calling.ex")

# Verify request classification is working
test_questions = [
  "What is the Avenua Connections?",
  "Who mentioned baseball?", 
  "Send an email to john@example.com"
]

IO.puts "Testing request classification:"
for question <- test_questions do
  result = AiAgent.LLM.ToolCalling.is_complex_request?(question)
  IO.puts "  '#{question}' -> #{result}"
end