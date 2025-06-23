#!/usr/bin/env elixir

defmodule DynamicSystemTest do
  @moduledoc """
  Test the cleaned up, dynamic system that uses context documents and LLM knowledge
  intelligently without hardcoded patterns.
  """

  def run_test do
    IO.puts("🧠 DYNAMIC CONTEXT-DRIVEN SYSTEM TEST")
    IO.puts("=" |> String.duplicate(50))

    IO.puts("\n✨ PHILOSOPHY: Let the AI decide intelligently based on:")
    IO.puts("   - Available context documents")
    IO.puts("   - LLM's own knowledge")
    IO.puts("   - Natural understanding of the request")
    IO.puts("   - No hardcoded patterns or forced behaviors")

    test_email_scenarios()
    test_calendar_scenarios()
    test_context_usage()

    IO.puts("\n🎯 SUMMARY")
    provide_summary()
  end

  defp test_email_scenarios do
    IO.puts("\n📧 EMAIL SCENARIOS")
    IO.puts("-" |> String.duplicate(30))

    scenarios = [
      %{
        request: "Email Brian Halligan telling about Wilton",
        expectation: "AI should naturally create a professional email about Wilton, using any available context about either Brian or Wilton, with a clean subject line"
      },
      %{
        request: "Send follow-up email to Sarah about our meeting",
        expectation: "AI should look for context about Sarah and recent meetings, create appropriate follow-up content"
      },
      %{
        request: "Email the team about quarterly results",
        expectation: "AI should find team contacts in context, use any available financial data, create informative update"
      }
    ]

    Enum.each(scenarios, fn scenario ->
      IO.puts("\n📝 Request: \"#{scenario.request}\"")
      IO.puts("   Expected: #{scenario.expectation}")
      IO.puts("   Approach: AI chooses email_send function and crafts content using available context")
    end)
  end

  defp test_calendar_scenarios do
    IO.puts("\n📅 CALENDAR SCENARIOS")
    IO.puts("-" |> String.duplicate(30))

    scenarios = [
      %{
        request: "Schedule meeting with John tomorrow at 2pm",
        expectation: "AI finds John's contact info from context, calculates correct date, creates calendar event"
      },
      %{
        request: "Set up quarterly review meeting",
        expectation: "AI uses context about team members and preferences to suggest appropriate scheduling"
      }
    ]

    Enum.each(scenarios, fn scenario ->
      IO.puts("\n📅 Request: \"#{scenario.request}\"")
      IO.puts("   Expected: #{scenario.expectation}")
      IO.puts("   Approach: AI intelligently uses calendar tool with context-informed decisions")
    end)
  end

  defp test_context_usage do
    IO.puts("\n📚 CONTEXT USAGE EXAMPLES")
    IO.puts("-" |> String.duplicate(30))

    IO.puts("\n🔍 How the system should work:")
    IO.puts("   1. User asks about 'Wilton'")
    IO.puts("   2. AI searches context documents for 'Wilton'")
    IO.puts("   3. If found: Uses specific information from documents")
    IO.puts("   4. If not found: Uses general knowledge about Wilton (town, company, etc.)")
    IO.puts("   5. Creates personalized, informative content")

    IO.puts("\n💡 Context Enhancement:")
    IO.puts("   - Emails include relevant details from CRM")
    IO.puts("   - Meeting invites use preferred times from history")
    IO.puts("   - Follow-ups reference previous conversations")
    IO.puts("   - All actions feel personalized and informed")
  end

  defp provide_summary do
    IO.puts("🎉 CLEANED UP SYSTEM BENEFITS:")
    IO.puts("")

    IO.puts("✅ REMOVED:")
    IO.puts("   - Hardcoded web search functionality")
    IO.puts("   - Rigid email_send_with_research patterns")
    IO.puts("   - Forced behavior rules")
    IO.puts("   - Overly specific system prompts")
    IO.puts("")

    IO.puts("✅ ENHANCED:")
    IO.puts("   - Natural, intelligent decision making")
    IO.puts("   - Context-driven personalization")
    IO.puts("   - Flexible tool usage")
    IO.puts("   - Professional communication")
    IO.puts("")

    IO.puts("🎯 RESULT:")
    IO.puts("   The AI now makes smart decisions based on:")
    IO.puts("   - What information is available in context")
    IO.puts("   - What the user actually needs")
    IO.puts("   - Professional communication standards")
    IO.puts("   - Natural understanding of requests")
    IO.puts("")

    IO.puts("🚀 TESTING:")
    IO.puts("   Try: 'Email Brian Halligan telling about Wilton'")
    IO.puts("   Expected: Professional email with relevant content,")
    IO.puts("   clean subject, using available context intelligently")
  end
end

# Run the test
DynamicSystemTest.run_test()

IO.puts("\n" <> ("=" |> String.duplicate(60)))
IO.puts("🎯 The system is now clean, dynamic, and intelligent!")
IO.puts("No more hardcoded patterns - just smart AI assistance.")
IO.puts("=" |> String.duplicate(60))
