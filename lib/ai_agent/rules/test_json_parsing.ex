defmodule AiAgent.Rules.TestJSONParsing do
  @moduledoc """
  Test module to verify JSON parsing in proactive rules works correctly.
  """

  require Logger
  alias AiAgent.Rules

  def test_json_parsing() do
    Logger.info("=== Testing JSON Parsing for Proactive Rules ===")

    # Test data with JSON strings (as they would come from the form)
    test_params = %{
      "user_id" => 1,
      "name" => "Test Rule",
      "description" => "Test rule for JSON parsing",
      "trigger_type" => "email_received",
      "trigger_conditions" => ~s({"sender_not_in_hubspot":true,"sender_email":"contains:@example.com"}),
      "actions" => ~s({"create_hubspot_contact":{"properties":{"email":"{{sender_email}}","firstname":"{{sender_name}}","lifecyclestage":"lead"}}}),
      "is_active" => true
    }

    Logger.info("Original params: #{inspect(test_params)}")

    # Apply the same parsing logic as the LiveView
    parsed_params = parse_json_fields(test_params)

    Logger.info("Parsed params: #{inspect(parsed_params)}")

    # Verify the parsing worked correctly
    case parsed_params do
      %{
        "trigger_conditions" => trigger_conditions,
        "actions" => actions
      } when is_map(trigger_conditions) and is_map(actions) ->
        Logger.info("✅ JSON parsing successful!")
        Logger.info("Trigger conditions: #{inspect(trigger_conditions)}")
        Logger.info("Actions: #{inspect(actions)}")
        
        # Test that we can create a rule with these params
        test_rule_creation(parsed_params)

      _ ->
        Logger.error("❌ JSON parsing failed!")
        {:error, "JSON parsing failed"}
    end
  end

  defp test_rule_creation(params) do
    case Rules.create_proactive_rule(params) do
      {:ok, rule} ->
        Logger.info("✅ Rule creation successful!")
        Logger.info("Created rule: #{rule.name}")
        Logger.info("Rule conditions: #{inspect(rule.trigger_conditions)}")
        Logger.info("Rule actions: #{inspect(rule.actions)}")
        
        # Clean up
        Rules.delete_proactive_rule(rule)
        Logger.info("✅ Test complete, rule cleaned up")
        
        {:ok, rule}
      
      {:error, changeset} ->
        Logger.error("❌ Rule creation failed!")
        Logger.error("Errors: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp parse_json_fields(params) do
    params
    |> parse_json_field("trigger_conditions")
    |> parse_json_field("actions")
  end

  defp parse_json_field(params, field_name) do
    case Map.get(params, field_name) do
      nil -> params
      "" -> Map.put(params, field_name, %{})
      json_string when is_binary(json_string) ->
        case Jason.decode(json_string) do
          {:ok, parsed} -> Map.put(params, field_name, parsed)
          {:error, _} -> 
            # Keep the original string so validation can catch the error
            params
        end
      value -> 
        # Already parsed or not a string
        Map.put(params, field_name, value)
    end
  end

  def test_invalid_json() do
    Logger.info("=== Testing Invalid JSON Handling ===")

    invalid_params = %{
      "user_id" => 1,
      "name" => "Invalid JSON Test",
      "description" => "Test invalid JSON handling",
      "trigger_type" => "email_received",
      "trigger_conditions" => ~s({"invalid": json}),
      "actions" => ~s({"valid": "action"}),
      "is_active" => true
    }

    parsed_params = parse_json_fields(invalid_params)
    
    case Rules.create_proactive_rule(parsed_params) do
      {:ok, _rule} ->
        Logger.error("❌ Should have failed with invalid JSON")
        
      {:error, changeset} ->
        Logger.info("✅ Correctly rejected invalid JSON")
        Logger.info("Validation errors: #{inspect(changeset.errors)}")
    end
  end
end