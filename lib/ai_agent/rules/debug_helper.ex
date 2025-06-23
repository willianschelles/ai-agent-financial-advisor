defmodule AiAgent.Rules.DebugHelper do
  @moduledoc """
  Helper functions to debug proactive rules JSON parsing and validation.
  """

  require Logger
  alias AiAgent.Rules

  @doc """
  Test the exact JSON strings you're trying to submit.
  """
  def test_your_json(user_id \\ 1) do
    Logger.info("=== Testing Your Exact JSON ===")
    
    # These are the exact JSON strings from your example
    trigger_conditions_json = ~s({"sender_not_in_hubspot":true,"sender_email":"contains:@example.com"})
    actions_json = ~s({"create_hubspot_contact":{"properties":{"email":"{{sender_email}}","firstname":"{{sender_name}}","lifecyclestage":"lead"}}})
    
    params = %{
      "user_id" => user_id,
      "name" => "When someone emails me that's not in HubSpot, add them as a contact",
      "description" => "test",
      "trigger_type" => "email_received",
      "trigger_conditions" => trigger_conditions_json,
      "actions" => actions_json,
      "is_active" => "false"  # This comes as string from form
    }
    
    Logger.info("Form params: #{inspect(params)}")
    
    # Apply the same parsing as the LiveView
    parsed_params = parse_json_fields(params)
    
    Logger.info("Parsed params: #{inspect(parsed_params)}")
    
    # Try to create the rule
    case Rules.create_proactive_rule(parsed_params) do
      {:ok, rule} ->
        Logger.info("✅ SUCCESS! Rule created:")
        Logger.info("  ID: #{rule.id}")
        Logger.info("  Name: #{rule.name}")
        Logger.info("  Trigger conditions: #{inspect(rule.trigger_conditions)}")
        Logger.info("  Actions: #{inspect(rule.actions)}")
        Logger.info("  Active: #{rule.is_active}")
        
        # Clean up
        Rules.delete_proactive_rule(rule)
        Logger.info("✅ Test rule cleaned up")
        
        {:ok, rule}
      
      {:error, changeset} ->
        Logger.error("❌ FAILED! Validation errors:")
        Enum.each(changeset.errors, fn {field, {msg, _}} ->
          Logger.error("  #{field}: #{msg}")
        end)
        Logger.error("Changeset: #{inspect(changeset)}")
        {:error, changeset}
    end
  end

  @doc """
  Test invalid JSON to make sure validation works.
  """
  def test_invalid_json(user_id \\ 1) do
    Logger.info("=== Testing Invalid JSON Validation ===")
    
    params = %{
      "user_id" => user_id,
      "name" => "Invalid JSON Test",
      "description" => "Should fail",
      "trigger_type" => "email_received",
      "trigger_conditions" => ~s({"invalid": json}),  # Invalid JSON
      "actions" => ~s({"valid": "action"}),
      "is_active" => "true"
    }
    
    parsed_params = parse_json_fields(params)
    
    case Rules.create_proactive_rule(parsed_params) do
      {:ok, _rule} ->
        Logger.error("❌ Should have failed with invalid JSON!")
        
      {:error, changeset} ->
        Logger.info("✅ Correctly rejected invalid JSON")
        Enum.each(changeset.errors, fn {field, {msg, _}} ->
          Logger.info("  #{field}: #{msg}")
        end)
    end
  end

  # Copy the parsing functions from the LiveView for testing
  defp parse_json_fields(params) do
    params
    |> parse_json_field("trigger_conditions")
    |> parse_json_field("actions")
    |> parse_boolean_field("is_active")
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

  defp parse_boolean_field(params, field_name) do
    case Map.get(params, field_name) do
      "true" -> Map.put(params, field_name, true)
      "false" -> Map.put(params, field_name, false)
      value when is_boolean(value) -> params
      _ -> params
    end
  end
end