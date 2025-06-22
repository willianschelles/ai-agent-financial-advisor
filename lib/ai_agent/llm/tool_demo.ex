defmodule AiAgent.LLM.ToolDemo do
  @moduledoc """
  Demo and testing functions for the tool calling system.
  Shows how to use tools for scheduling, emailing, and CRM actions.
  """

  require Logger

  alias AiAgent.LLM.ToolCalling
  alias AiAgent.User
  alias AiAgent.Repo

  @doc """
  Complete tool calling demonstration with sample requests.

  ## Usage in IEx:
  iex> AiAgent.LLM.ToolDemo.run_complete_demo()
  """
  def run_complete_demo do
    IO.puts("🤖 === TOOL CALLING SYSTEM DEMO ===")
    IO.puts("This demo shows the complete tool calling pipeline:")
    IO.puts("1. Natural language requests")
    IO.puts("2. Tool selection and execution")
    IO.puts("3. Action completion and responses")
    IO.puts("")

    # Setup test user
    IO.puts("👤 Step 1: Setting up test user...")
    user = setup_demo_user()

    # Run various tool calling scenarios
    IO.puts("\n🔧 Step 2: Testing tool calling scenarios...")
    run_demo_scenarios(user)

    # Show available tools
    IO.puts("\n📋 Step 3: Available tools overview...")
    show_available_tools()

    IO.puts("\n✅ Tool calling demo completed!")
  end

  @doc """
  Test tool calling with a specific user request.

  ## Usage:
  iex> user = AiAgent.Repo.get_by(AiAgent.User, email: "your-email")
  iex> AiAgent.LLM.ToolDemo.test_request(user, "Schedule a meeting with John tomorrow at 2pm")
  """
  def test_request(user, request) do
    IO.puts("🧪 Testing tool calling with request:")
    IO.puts("   \"#{request}\"")
    IO.puts("")

    start_time = System.monotonic_time(:millisecond)

    case ToolCalling.ask_with_tools(user, request) do
      {:ok, result} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        IO.puts("✅ Tool Calling Response:")
        IO.puts("#{result.response}")
        IO.puts("")

        if length(result.tools_used) > 0 do
          IO.puts("🔧 Tools Used:")

          Enum.each(result.tools_used, fn tool ->
            status_icon = if tool.success, do: "✅", else: "❌"
            IO.puts("  #{status_icon} #{tool.tool}.#{tool.function}")

            if tool.success do
              IO.puts("     Result: #{inspect(tool.result)}")
            else
              IO.puts("     Error: #{tool.result}")
            end
          end)

          IO.puts("")
        end

        if length(result.context_used) > 0 do
          IO.puts("📄 Context Used:")

          Enum.each(result.context_used, fn doc ->
            IO.puts(
              "  • #{doc.type} from #{doc.source} (similarity: #{Float.round(doc.similarity, 3)})"
            )
          end)

          IO.puts("")
        end

        IO.puts("📊 Metadata:")
        IO.puts("  Duration: #{duration}ms")
        IO.puts("  Tools enabled: #{result.metadata.tools_enabled}")
        IO.puts("  Tool calls made: #{result.metadata.tool_calls_made}")
        IO.puts("  Context documents: #{length(result.context_used)}")

        result

      {:error, reason} ->
        IO.puts("❌ Tool calling failed: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Test individual tools directly.

  ## Usage:
  iex> AiAgent.LLM.ToolDemo.test_individual_tools(user)
  """
  def test_individual_tools(user) do
    IO.puts("🔨 Testing individual tools...")
    IO.puts("")

    # Test Calendar Tool
    IO.puts("📅 Testing Calendar Tool...")
    test_calendar_tool(user)

    IO.puts("\n📧 Testing Email Tool...")
    test_email_tool(user)

    IO.puts("\n🏢 Testing HubSpot Tool...")
    test_hubspot_tool(user)

    IO.puts("\n✅ Individual tool testing completed!")
  end

  @doc """
  Show benchmark results for tool calling performance.
  """
  def benchmark_tool_performance(user, test_requests \\ nil) do
    requests =
      test_requests ||
        [
          "Schedule a meeting with Sarah Johnson tomorrow at 2pm to discuss her portfolio",
          "Send an email to John Smith about the quarterly review",
          "Add a note in HubSpot for Mike Wilson about his retirement planning interest",
          "Find email addresses for everyone at Tech Corp",
          "Create a deal in HubSpot for the Johnson family college planning worth $50000"
        ]

    IO.puts("⏱️  Tool Calling Performance Benchmark")
    IO.puts("Testing #{length(requests)} requests...")
    IO.puts("")

    results =
      Enum.map(requests, fn request ->
        start_time = System.monotonic_time(:millisecond)

        result =
          case ToolCalling.ask_with_tools(user, request) do
            {:ok, response} ->
              {
                :success,
                String.length(response.response),
                length(response.tools_used),
                length(response.context_used)
              }

            {:error, _} ->
              {:error, 0, 0, 0}
          end

        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        {request, result, duration}
      end)

    # Display results
    total_time = Enum.sum(Enum.map(results, fn {_, _, duration} -> duration end))
    successful = Enum.count(results, fn {_, {status, _, _, _}, _} -> status == :success end)

    IO.puts("📊 Results:")
    IO.puts("  Total requests: #{length(requests)}")
    IO.puts("  Successful: #{successful}")
    IO.puts("  Total time: #{total_time}ms")
    IO.puts("  Average time per request: #{round(total_time / length(requests))}ms")
    IO.puts("")

    IO.puts("📋 Individual Results:")

    Enum.each(results, fn {request, {status, response_length, tools_used, docs_used}, duration} ->
      status_icon = if status == :success, do: "✅", else: "❌"

      IO.puts(
        "  #{status_icon} #{duration}ms | #{tools_used} tools | #{docs_used} docs | #{response_length} chars"
      )

      IO.puts("     #{String.slice(request, 0, 60)}...")
    end)

    results
  end

  # Private helper functions

  defp setup_demo_user do
    email = "tool_demo@example.com"

    case Repo.get_by(User, email: email) do
      nil ->
        user =
          Repo.insert!(%User{
            email: email,
            google_tokens: %{"access_token" => "demo_google_token"},
            hubspot_tokens: %{"access_token" => "demo_hubspot_token"}
          })

        IO.puts("✅ Created demo user: #{email}")
        user

      user ->
        IO.puts("✅ Using existing demo user: #{email}")
        user
    end
  end

  defp run_demo_scenarios(user) do
    demo_requests = [
      "Who mentioned baseball in their emails?",
      "Schedule a meeting with John Smith tomorrow at 2pm",
      "Send an email to Sarah about her portfolio performance",
      "Add a note in HubSpot that Mike Wilson is interested in retirement planning",
      "Create a deal for the Johnson family college savings plan worth $25000"
    ]

    Enum.each(demo_requests, fn request ->
      IO.puts("🎯 Request: \"#{request}\"")

      case ToolCalling.ask_with_tools(user, request) do
        {:ok, result} ->
          IO.puts("🤖 Response: #{String.slice(result.response, 0, 150)}...")

          if length(result.tools_used) > 0 do
            tools_summary =
              result.tools_used
              |> Enum.map(fn tool ->
                status = if tool.success, do: "✅", else: "❌"
                "#{status} #{tool.tool}.#{tool.function}"
              end)
              |> Enum.join(", ")

            IO.puts("🔧 Tools: #{tools_summary}")
          end

        {:error, reason} ->
          IO.puts("❌ Error: #{reason}")
      end

      IO.puts("")
    end)
  end

  defp show_available_tools do
    tools = ToolCalling.get_available_tools()

    IO.puts("📋 Available Tools (#{length(tools)} functions):")
    IO.puts("")

    grouped_tools =
      Enum.group_by(tools, fn tool ->
        tool.function.name |> String.split("_") |> hd()
      end)

    Enum.each(grouped_tools, fn {category, category_tools} ->
      IO.puts("📂 #{String.upcase(category)} Tools:")

      Enum.each(category_tools, fn tool ->
        IO.puts("  • #{tool.function.name}")
        IO.puts("    #{tool.function.description}")
      end)

      IO.puts("")
    end)
  end

  defp test_calendar_tool(user) do
    # Test calendar event creation
    calendar_args = %{
      "title" => "Demo Meeting",
      "start_time" => "2024-01-15T14:00:00-05:00",
      "end_time" => "2024-01-15T15:00:00-05:00",
      "description" => "Test meeting created by tool demo"
    }

    case ToolCalling.execute_tool(user, "calendar", "calendar_create_event", calendar_args) do
      {:ok, result} ->
        IO.puts("  ✅ Calendar event creation: #{result.message}")

      {:error, reason} ->
        IO.puts("  ❌ Calendar event creation failed: #{reason}")
    end

    # Test free time finding
    free_time_args = %{
      "start_date" => "2024-01-15",
      "end_date" => "2024-01-16",
      "duration_minutes" => 60
    }

    case ToolCalling.execute_tool(user, "calendar", "calendar_find_free_time", free_time_args) do
      {:ok, result} ->
        IO.puts("  ✅ Free time search: #{result.message}")

      {:error, reason} ->
        IO.puts("  ❌ Free time search failed: #{reason}")
    end
  end

  defp test_email_tool(user) do
    # Test email drafting
    draft_args = %{
      "recipient_name" => "John Doe",
      "purpose" => "follow up on meeting",
      "key_points" => ["Discussed portfolio performance", "Next steps for Q1"],
      "tone" => "professional"
    }

    case ToolCalling.execute_tool(user, "email", "email_draft", draft_args) do
      {:ok, result} ->
        IO.puts("  ✅ Email drafting: #{result.message}")

      {:error, reason} ->
        IO.puts("  ❌ Email drafting failed: #{reason}")
    end

    # Test contact finding
    contact_args = %{
      "name" => "John Smith",
      "context_hint" => "baseball"
    }

    case ToolCalling.execute_tool(user, "email", "email_find_contact", contact_args) do
      {:ok, result} ->
        IO.puts("  ✅ Contact search: #{result.message}")

      {:error, reason} ->
        IO.puts("  ❌ Contact search failed: #{reason}")
    end
  end

  defp test_hubspot_tool(user) do
    # Test contact creation
    contact_args = %{
      "email" => "demo@example.com",
      "first_name" => "Demo",
      "last_name" => "Contact",
      "company" => "Demo Corp",
      "notes" => "Created during tool demo"
    }

    case ToolCalling.execute_tool(user, "hubspot", "hubspot_create_contact", contact_args) do
      {:ok, result} ->
        IO.puts("  ✅ Contact creation: #{result.message}")

      {:error, reason} ->
        IO.puts("  ❌ Contact creation failed: #{reason}")
    end

    # Test contact search
    search_args = %{
      "query" => "Demo Corp",
      "limit" => 5
    }

    case ToolCalling.execute_tool(user, "hubspot", "hubspot_search_contacts", search_args) do
      {:ok, result} ->
        IO.puts("  ✅ Contact search: #{result.message}")

      {:error, reason} ->
        IO.puts("  ❌ Contact search failed: #{reason}")
    end
  end
end
