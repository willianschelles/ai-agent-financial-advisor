defmodule AiAgent.Rules.Demo do
  @moduledoc """
  Demo module to test proactive rules functionality.
  """

  require Logger
  alias AiAgent.{Rules, Accounts}
  alias AiAgent.Rules.RuleEngine

  @doc """
  Create a sample proactive rule for testing.
  """
  def create_sample_rule(user_id) do
    rule_params = %{
      user_id: user_id,
      name: "Auto-add new email contacts to HubSpot",
      description: "When someone emails me that's not in HubSpot, add them as a contact",
      trigger_type: "email_received",
      trigger_conditions: %{
        "sender_not_in_hubspot" => true,
        "sender_email" => "contains:@"
      },
      actions: %{
        "create_hubspot_contact" => %{
          "properties" => %{
            "email" => "{{sender_email}}",
            "firstname" => "{{sender_name}}",
            "lifecyclestage" => "lead",
            "source" => "email_automation"
          }
        },
        "send_notification" => %{
          "message" => "New lead added to HubSpot: {{sender_email}}"
        }
      },
      is_active: true
    }

    case Rules.create_proactive_rule(rule_params) do
      {:ok, rule} ->
        Logger.info("Created sample rule: #{rule.name}")
        {:ok, rule}
      
      {:error, changeset} ->
        Logger.error("Failed to create sample rule: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Test rule execution with sample email event.
  """
  def test_email_rule_execution(user_id) do
    # Sample email event data
    email_event = %{
      "sender_email" => "john.doe@example.com",
      "sender_name" => "John Doe",
      "subject" => "Inquiry about your services",
      "message_id" => "test-message-123",
      "timestamp" => DateTime.utc_now(),
      "sender_not_in_hubspot" => true
    }

    Logger.info("Testing rule execution with email event: #{inspect(email_event)}")

    case RuleEngine.process_event(user_id, "email_received", email_event) do
      {:ok, results} ->
        Logger.info("Rule execution completed. Results: #{inspect(results)}")
        {:ok, results}
      
      {:error, reason} ->
        Logger.error("Rule execution failed: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Create a calendar-based proactive rule.
  """
  def create_calendar_rule(user_id) do
    rule_params = %{
      user_id: user_id,
      name: "Auto-create HubSpot notes for new meetings",
      description: "When a meeting is scheduled, create a note in HubSpot for the main attendee",
      trigger_type: "calendar_event",
      trigger_conditions: %{
        "event_type" => "created",
        "attendees_count" => ">1"
      },
      actions: %{
        "create_hubspot_note" => %{
          "content" => "Meeting scheduled: {{event_title}} on {{event_date}}",
          "contact_email" => "{{attendee_email}}"
        }
      },
      is_active: true
    }

    case Rules.create_proactive_rule(rule_params) do
      {:ok, rule} ->
        Logger.info("Created calendar rule: #{rule.name}")
        {:ok, rule}
      
      {:error, changeset} ->
        Logger.error("Failed to create calendar rule: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Run a full demo with both rule creation and testing.
  """
  def run_full_demo(user_email \\ "test@example.com") do
    Logger.info("=== PROACTIVE RULES DEMO ===")

    # Find or create test user
    user = case Accounts.get_user_by_email(user_email) do
      nil ->
        Logger.info("Creating test user: #{user_email}")
        {:ok, user} = Accounts.create_user(%{
          email: user_email,
          name: "Test User"
        })
        user
      
      user ->
        Logger.info("Using existing user: #{user.email}")
        user
    end

    # Create sample rules
    Logger.info("Creating sample proactive rules...")
    {:ok, email_rule} = create_sample_rule(user.id)
    {:ok, calendar_rule} = create_calendar_rule(user.id)

    # List all rules for user
    rules = Rules.list_proactive_rules(user.id)
    Logger.info("User has #{length(rules)} proactive rules")

    # Test email rule execution
    Logger.info("Testing email rule execution...")
    {:ok, email_results} = test_email_rule_execution(user.id)

    # Test calendar rule execution
    Logger.info("Testing calendar rule execution...")
    calendar_event = %{
      "event_type" => "created",
      "event_title" => "Sales Meeting",
      "event_date" => "2024-01-15 10:00:00",
      "attendee_email" => "prospect@company.com",
      "attendees_count" => 2
    }

    {:ok, calendar_results} = RuleEngine.process_event(user.id, "calendar_event", calendar_event)

    Logger.info("=== DEMO COMPLETE ===")
    Logger.info("Email rule results: #{length(email_results)} actions executed")
    Logger.info("Calendar rule results: #{length(calendar_results)} actions executed")

    %{
      user: user,
      rules: [email_rule, calendar_rule],
      email_results: email_results,
      calendar_results: calendar_results
    }
  end

  @doc """
  Clean up demo data.
  """
  def cleanup_demo_data(user_email \\ "test@example.com") do
    case Accounts.get_user_by_email(user_email) do
      nil ->
        Logger.info("No demo user found")
        :ok
      
      user ->
        rules = Rules.list_proactive_rules(user.id)
        
        Enum.each(rules, fn rule ->
          Rules.delete_proactive_rule(rule)
          Logger.info("Deleted rule: #{rule.name}")
        end)
        
        Logger.info("Cleaned up #{length(rules)} demo rules")
        :ok
    end
  end
end