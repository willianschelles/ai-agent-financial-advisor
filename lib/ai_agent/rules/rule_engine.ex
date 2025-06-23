defmodule AiAgent.Rules.RuleEngine do
  @moduledoc """
  Rule evaluation engine that processes events and executes proactive actions.
  """

  require Logger
  alias AiAgent.Rules
  alias AiAgent.Rules.ProactiveRule
  alias AiAgent.LLM.Tools.{EmailTool, CalendarTool, HubspotTool}

  @doc """
  Process an event and execute any matching proactive rules.
  """
  def process_event(user_id, trigger_type, event_data) do
    Logger.info("Processing event for user #{user_id}: #{trigger_type}")
    
    matching_rules = Rules.find_matching_rules(user_id, trigger_type, event_data)
    
    Logger.info("Found #{length(matching_rules)} matching rules")
    
    results = 
      matching_rules
      |> Enum.map(&execute_rule(&1, event_data))
      |> Enum.filter(& &1 != nil)
    
    {:ok, results}
  end

  defp execute_rule(%ProactiveRule{} = rule, event_data) do
    Logger.info("Executing rule: #{rule.name}")
    
    try do
      actions = rule.actions || %{}
      
      action_results = 
        actions
        |> Enum.map(fn {action_type, action_config} ->
          execute_action(rule.user_id, action_type, action_config, event_data)
        end)
        |> Enum.filter(& &1 != nil)
      
      %{
        rule_id: rule.id,
        rule_name: rule.name,
        actions_executed: length(action_results),
        action_results: action_results,
        success: true
      }
    rescue
      error ->
        Logger.error("Error executing rule #{rule.name}: #{inspect(error)}")
        %{
          rule_id: rule.id,
          rule_name: rule.name,
          error: inspect(error),
          success: false
        }
    end
  end

  defp execute_action(user_id, action_type, action_config, event_data) do
    Logger.info("Executing action: #{action_type}")
    
    # Interpolate variables in action config
    interpolated_config = interpolate_variables(action_config, event_data)
    
    case action_type do
      "create_hubspot_contact" ->
        execute_hubspot_contact_action(user_id, interpolated_config)
      
      "create_hubspot_note" ->
        execute_hubspot_note_action(user_id, interpolated_config)
      
      "send_email" ->
        execute_email_action(user_id, interpolated_config)
      
      "create_calendar_event" ->
        execute_calendar_action(user_id, interpolated_config)
      
      "send_notification" ->
        execute_notification_action(user_id, interpolated_config)
      
      _ ->
        Logger.warning("Unknown action type: #{action_type}")
        nil
    end
  end

  defp execute_hubspot_contact_action(user_id, config) do
    properties = Map.get(config, "properties", %{})
    
    case HubspotTool.create_contact(user_id, properties) do
      {:ok, contact} ->
        Logger.info("Created HubSpot contact: #{inspect(contact)}")
        %{action: "create_hubspot_contact", success: true, result: contact}
      
      {:error, reason} ->
        Logger.error("Failed to create HubSpot contact: #{reason}")
        %{action: "create_hubspot_contact", success: false, error: reason}
    end
  end

  defp execute_hubspot_note_action(user_id, config) do
    content = Map.get(config, "content", "")
    contact_email = Map.get(config, "contact_email")
    
    case HubspotTool.create_note(user_id, contact_email, content) do
      {:ok, note} ->
        Logger.info("Created HubSpot note: #{inspect(note)}")
        %{action: "create_hubspot_note", success: true, result: note}
      
      {:error, reason} ->
        Logger.error("Failed to create HubSpot note: #{reason}")
        %{action: "create_hubspot_note", success: false, error: reason}
    end
  end

  defp execute_email_action(user_id, config) do
    to = Map.get(config, "to", [])
    subject = Map.get(config, "subject", "")
    body = Map.get(config, "body", "")
    
    case EmailTool.send_email(user_id, to, subject, body) do
      {:ok, result} ->
        Logger.info("Sent email: #{inspect(result)}")
        %{action: "send_email", success: true, result: result}
      
      {:error, reason} ->
        Logger.error("Failed to send email: #{reason}")
        %{action: "send_email", success: false, error: reason}
    end
  end

  defp execute_calendar_action(user_id, config) do
    event_data = %{
      "summary" => Map.get(config, "title", ""),
      "description" => Map.get(config, "description", ""),
      "start_time" => Map.get(config, "start_time"),
      "end_time" => Map.get(config, "end_time"),
      "attendees" => Map.get(config, "attendees", [])
    }
    
    case CalendarTool.create_event(user_id, event_data) do
      {:ok, event} ->
        Logger.info("Created calendar event: #{inspect(event)}")
        %{action: "create_calendar_event", success: true, result: event}
      
      {:error, reason} ->
        Logger.error("Failed to create calendar event: #{reason}")
        %{action: "create_calendar_event", success: false, error: reason}
    end
  end

  defp execute_notification_action(user_id, config) do
    message = Map.get(config, "message", "")
    
    # For now, just log the notification
    # In a real system, you might send push notifications, emails, etc.
    Logger.info("Notification for user #{user_id}: #{message}")
    
    %{action: "send_notification", success: true, result: %{message: message}}
  end

  defp interpolate_variables(config, event_data) when is_map(config) do
    config
    |> Enum.map(fn {key, value} ->
      {key, interpolate_variables(value, event_data)}
    end)
    |> Map.new()
  end

  defp interpolate_variables(value, event_data) when is_binary(value) do
    # Replace {{variable}} with values from event_data
    Regex.replace(~r/\{\{([^}]+)\}\}/, value, fn _match, variable ->
      get_nested_value(event_data, String.trim(variable)) || "{{#{variable}}}"
    end)
  end

  defp interpolate_variables(value, _event_data), do: value

  defp get_nested_value(data, path) when is_map(data) do
    path
    |> String.split(".")
    |> Enum.reduce(data, fn key, acc ->
      case acc do
        %{} -> Map.get(acc, key) || Map.get(acc, String.to_atom(key))
        _ -> nil
      end
    end)
    |> case do
      nil -> nil
      value -> to_string(value)
    end
  end

  defp get_nested_value(_data, _path), do: nil
end