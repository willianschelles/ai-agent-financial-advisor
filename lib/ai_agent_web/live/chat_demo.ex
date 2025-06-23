defmodule AiAgentWeb.ChatDemo do
  @moduledoc """
  Demo module to showcase the enhanced chat UI features.
  """

  require Logger

  @doc """
  Simulate a multi-turn conversation with tool usage for demo purposes.
  """
  def simulate_demo_conversation() do
    Logger.info("=== Chat UI Demo Simulation ===")
    
    demo_messages = [
      %{
        role: "user",
        content: "Find all emails from new prospects this week",
        timestamp: DateTime.add(DateTime.utc_now(), -300, :second)
      },
      %{
        role: "assistant",
        content: "I found 3 emails from new prospects this week. Here's what I discovered:\n\n1. **Sarah Johnson** (sarah@techstartup.com) - Interested in our premium package\n2. **Mike Chen** (m.chen@consulting.biz) - Asking about enterprise solutions  \n3. **Lisa Rodriguez** (lisa@marketing-pro.com) - Wants a demo next week\n\nI've also created HubSpot contacts for each of them automatically.",
        status: "completed",
        context_sources: ["Gmail Inbox", "Gmail Sent"],
        tools_used: [
          %{name: "Gmail Search", success: true, description: "Searched for new prospect emails"},
          %{name: "HubSpot Contact Creation", success: true, description: "Created 3 new contacts"}
        ],
        timestamp: DateTime.add(DateTime.utc_now(), -280, :second)
      },
      %{
        role: "user", 
        content: "Schedule a follow-up meeting with Sarah for tomorrow at 2 PM",
        timestamp: DateTime.add(DateTime.utc_now(), -200, :second)
      },
      %{
        role: "assistant",
        content: "I've successfully scheduled a follow-up meeting with Sarah Johnson:\n\n**Meeting Details:**\n- **Date:** Tomorrow at 2:00 PM\n- **Duration:** 1 hour\n- **Attendees:** You and Sarah Johnson (sarah@techstartup.com)\n- **Location:** Google Meet (link included in invite)\n\nThe calendar invite has been sent to both of you, and I've added a note to her HubSpot record about this upcoming meeting.",
        status: "completed",
        context_sources: ["Google Calendar", "HubSpot CRM"],
        tools_used: [
          %{name: "Calendar Scheduling", success: true, description: "Created meeting for tomorrow 2 PM"},
          %{name: "Email Invitation", success: true, description: "Sent invite to Sarah Johnson"},
          %{name: "HubSpot Note", success: true, description: "Added meeting note to contact record"}
        ],
        timestamp: DateTime.add(DateTime.utc_now(), -150, :second)
      },
      %{
        role: "user",
        content: "What deals are closing this month?",
        timestamp: DateTime.add(DateTime.utc_now(), -60, :second)
      },
      %{
        role: "assistant", 
        content: "Based on your HubSpot pipeline data, here are the deals closing this month:\n\n**High Probability (80%+ chance)**\n- TechCorp Enterprise License - $45,000 (closes Dec 28)\n- Startup Solutions Package - $12,000 (closes Dec 30)\n\n**Medium Probability (50-79% chance)**  \n- Marketing Agency Retainer - $8,500/month (closes Dec 31)\n- Consulting Firm Upgrade - $25,000 (closes Dec 29)\n\n**Total Potential Revenue:** $90,500 one-time + $8,500 recurring\n\nI notice the TechCorp deal hasn't had activity in 5 days. Should I send a follow-up email?",
        status: "completed",
        context_sources: ["HubSpot Deals", "HubSpot Pipeline"],
        tools_used: [
          %{name: "HubSpot Query", success: true, description: "Retrieved deal pipeline data"},
          %{name: "Deal Analysis", success: true, description: "Calculated probabilities and totals"}
        ],
        timestamp: DateTime.add(DateTime.utc_now(), -30, :second)
      }
    ]

    %{
      demo_messages: demo_messages,
      features_showcased: [
        "Multi-turn conversation history",
        "Rich message formatting with markdown",
        "Tool execution feedback and status",
        "Context source attribution", 
        "Real-time status indicators",
        "Message timestamps and threading",
        "Retry functionality for failed messages",
        "Professional business assistant responses"
      ]
    }
  end

  @doc """
  Generate sample system status updates for demo.
  """
  def demo_system_statuses() do
    [
      "Searching knowledge base...",
      "Processing tools...",
      "Accessing Gmail API...",
      "Updating HubSpot records...",
      "Scheduling calendar event...",
      "Analyzing deal pipeline...",
      "Finalizing response..."
    ]
  end

  @doc """
  Generate sample tool progress for demo.
  """
  def demo_tool_progress() do
    [
      %{name: "Gmail Search", status: "completed", description: "Found 15 relevant emails"},
      %{name: "Contact Lookup", status: "completed", description: "Verified contact information"},
      %{name: "HubSpot Update", status: "failed", description: "API rate limit exceeded"},
      %{name: "Calendar Check", status: "completed", description: "Availability confirmed"}
    ]
  end

  @doc """
  Showcase the conversation context features.
  """
  def demo_conversation_context() do
    %{
      active_topics: ["Email management", "Calendar scheduling", "Deal pipeline"],
      mentioned_contacts: ["Sarah Johnson", "Mike Chen", "Lisa Rodriguez"],
      referenced_deals: ["TechCorp Enterprise", "Startup Solutions"],
      scheduled_meetings: ["Sarah Johnson - Tomorrow 2 PM"],
      context_retention: "Maintains context across multiple conversation turns"
    }
  end
end