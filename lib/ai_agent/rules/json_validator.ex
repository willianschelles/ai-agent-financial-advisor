defmodule AiAgent.Rules.JSONValidator do
  @moduledoc """
  Helper to validate and fix JSON issues.
  """

  require Logger

  @doc """
  Test the exact JSON you're having issues with.
  """
  def test_your_broken_json() do
    Logger.info("=== Testing Your Problematic JSON ===")
    
    # This is the JSON with the line break issue from your error
    broken_json = ~s({"create_hubspot_contact":{"properties":{"email":"{{sender_email}}","firstname":"{{sender_name}}","lifec
  yclestage":"lead"}}})
    
    Logger.info("Broken JSON:")
    Logger.info(broken_json)
    
    case Jason.decode(broken_json) do
      {:ok, parsed} ->
        Logger.info("✅ Surprisingly, this JSON parsed successfully!")
        Logger.info("Parsed: #{inspect(parsed)}")
        
      {:error, error} ->
        Logger.error("❌ JSON parsing failed:")
        Logger.error("Error: #{Exception.message(error)}")
        Logger.info("🔧 Suggested fix: Remove line breaks from property names")
    end
    
    # Show the corrected version
    Logger.info("\n=== Corrected Version ===")
    fixed_json = ~s({"create_hubspot_contact":{"properties":{"email":"{{sender_email}}","firstname":"{{sender_name}}","lifecyclestage":"lead"}}})
    
    Logger.info("Fixed JSON:")
    Logger.info(fixed_json)
    
    case Jason.decode(fixed_json) do
      {:ok, parsed} ->
        Logger.info("✅ Fixed JSON parses correctly!")
        Logger.info("Parsed: #{inspect(parsed)}")
        
      {:error, error} ->
        Logger.error("❌ Even fixed JSON failed: #{Exception.message(error)}")
    end
  end

  @doc """
  Clean JSON by removing problematic whitespace.
  """
  def clean_json(json_string) when is_binary(json_string) do
    json_string
    |> String.replace(~r/\n\s+/, "") # Remove newlines followed by spaces
    |> String.replace(~r/\s+/, " ")  # Normalize whitespace
    |> String.trim()
  end

  @doc """
  Validate and provide helpful error messages for JSON.
  """
  def validate_json(json_string) do
    cleaned = clean_json(json_string)
    
    case Jason.decode(cleaned) do
      {:ok, parsed} ->
        {:ok, parsed}
        
      {:error, %Jason.DecodeError{} = error} ->
        position = error.position || 0
        context = String.slice(cleaned, max(0, position - 10), 20)
        
        {:error, "JSON Error at position #{position} near '#{context}': #{error.data}"}
    end
  end

  @doc """
  Test a complete rule with problematic JSON.
  """
  def test_complete_rule_with_broken_json() do
    Logger.info("=== Testing Complete Rule Creation ===")
    
    # Simulate what comes from the form with line breaks
    params = %{
      "user_id" => 1,
      "name" => "Test Rule",
      "description" => "test", 
      "trigger_type" => "email_received",
      "trigger_conditions" => ~s({"sender_not_in_hubspot":true,"sender_email":"contains:@example.com"}),
      "actions" => ~s({"create_hubspot_contact":{"properties":{"email":"{{sender_email}}","firstname":"{{sender_name}}","lifec
  yclestage":"lead"}}}),
      "is_active" => "false"
    }
    
    Logger.info("Testing with broken actions JSON...")
    
    # Try to parse the actions
    case validate_json(params["actions"]) do
      {:ok, parsed} ->
        Logger.info("✅ Actions JSON parsed successfully after cleaning!")
        Logger.info("Parsed: #{inspect(parsed)}")
        
      {:error, msg} ->
        Logger.error("❌ Actions JSON still invalid: #{msg}")
    end
    
    # Show what the cleaned version looks like
    cleaned_actions = clean_json(params["actions"])
    Logger.info("Cleaned actions JSON: #{cleaned_actions}")
  end
end