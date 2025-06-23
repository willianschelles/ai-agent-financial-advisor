defmodule AiAgentWeb.RulesLive do
  use AiAgentWeb, :live_view

  alias AiAgent.Accounts
  alias AiAgent.Rules
  alias AiAgent.Rules.ProactiveRule

  def mount(_params, session, socket) do
    user = Accounts.get_user!(session["user_id"])
    rules = Rules.list_proactive_rules(user.id)
    
    {:ok, assign(socket, 
      current_user: user,
      rules: rules,
      show_form: false,
      current_rule: nil,
      form: nil
    )}
  end

  def handle_event("new_rule", _params, socket) do
    changeset = Rules.change_proactive_rule(%ProactiveRule{})
    
    {:noreply, assign(socket, 
      show_form: true,
      current_rule: nil,
      form: to_form(changeset)
    )}
  end

  def handle_event("edit_rule", %{"id" => id}, socket) do
    rule = Rules.get_user_proactive_rule(socket.assigns.current_user.id, id)
    
    # Convert maps back to JSON strings for form editing
    rule_with_json = %{rule | 
      trigger_conditions: Jason.encode!(rule.trigger_conditions || %{}, pretty: true),
      actions: Jason.encode!(rule.actions || %{}, pretty: true)
    }
    
    changeset = Rules.change_proactive_rule(rule_with_json)
    
    {:noreply, assign(socket, 
      show_form: true,
      current_rule: rule,
      form: to_form(changeset)
    )}
  end

  def handle_event("cancel_form", _params, socket) do
    {:noreply, assign(socket, show_form: false, current_rule: nil, form: nil)}
  end

  def handle_event("save_rule", %{"proactive_rule" => rule_params}, socket) do
    rule_params = 
      rule_params
      |> Map.put("user_id", socket.assigns.current_user.id)
      |> parse_json_fields()
    
    result = case socket.assigns.current_rule do
      nil -> Rules.create_proactive_rule(rule_params)
      rule -> Rules.update_proactive_rule(rule, rule_params)
    end

    case result do
      {:ok, _rule} ->
        rules = Rules.list_proactive_rules(socket.assigns.current_user.id)
        {:noreply, assign(socket, 
          rules: rules,
          show_form: false,
          current_rule: nil,
          form: nil
        )}
      
      {:error, changeset} ->
        # Convert maps back to JSON strings for display in form
        changeset_with_json = convert_maps_to_json_strings(changeset)
        {:noreply, assign(socket, form: to_form(changeset_with_json))}
    end
  end

  def handle_event("toggle_rule", %{"id" => id}, socket) do
    rule = Rules.get_user_proactive_rule(socket.assigns.current_user.id, id)
    
    case Rules.toggle_proactive_rule(rule) do
      {:ok, _rule} ->
        rules = Rules.list_proactive_rules(socket.assigns.current_user.id)
        {:noreply, assign(socket, rules: rules)}
      
      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_rule", %{"id" => id}, socket) do
    rule = Rules.get_user_proactive_rule(socket.assigns.current_user.id, id)
    
    case Rules.delete_proactive_rule(rule) do
      {:ok, _rule} ->
        rules = Rules.list_proactive_rules(socket.assigns.current_user.id)
        {:noreply, assign(socket, rules: rules)}
      
      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("update_conditions", %{"trigger_type" => trigger_type}, socket) do
    form = socket.assigns.form
    changeset = form.source
    
    updated_changeset = Ecto.Changeset.put_change(changeset, :trigger_type, trigger_type)
    
    {:noreply, assign(socket, form: to_form(updated_changeset))}
  end

  defp format_trigger_type("email_received"), do: "Email Received"
  defp format_trigger_type("calendar_event"), do: "Calendar Event"
  defp format_trigger_type("hubspot_contact_created"), do: "HubSpot Contact Created"
  defp format_trigger_type("hubspot_note_created"), do: "HubSpot Note Created"
  defp format_trigger_type(type), do: String.capitalize(type)

  defp get_example_conditions("email_received") do
    """
    {
      "sender_email": "contains:@example.com",
      "subject": "regex:.*urgent.*",
      "sender_not_in_hubspot": true
    }
    """
  end

  defp get_example_conditions("calendar_event") do
    """
    {
      "event_type": "created",
      "title": "contains:meeting",
      "attendees_count": ">1"
    }
    """
  end

  defp get_example_conditions("hubspot_contact_created") do
    """
    {
      "contact_source": "email",
      "lifecycle_stage": "lead"
    }
    """
  end

  defp get_example_conditions("hubspot_note_created") do
    """
    {
      "note_type": "call",
      "created_by": "user"
    }
    """
  end

  defp get_example_conditions(_), do: "{}"

  defp get_example_actions("email_received") do
    """
    {
      "create_hubspot_contact": {
        "properties": {
          "email": "{{sender_email}}",
          "firstname": "{{sender_name}}",
          "lifecyclestage": "lead"
        }
      },
      "send_notification": {
        "message": "New lead from email: {{sender_email}}"
      }
    }
    """
  end

  defp get_example_actions("calendar_event") do
    """
    {
      "create_hubspot_note": {
        "content": "Meeting scheduled: {{event_title}} on {{event_date}}",
        "contact_email": "{{attendee_email}}"
      }
    }
    """
  end

  defp get_example_actions(_) do
    """
    {
      "create_hubspot_contact": {
        "properties": {
          "email": "{{email}}",
          "lifecyclestage": "lead"
        }
      }
    }
    """
  end

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
        # Clean the JSON first to remove problematic whitespace
        cleaned_json = clean_json(json_string)
        case Jason.decode(cleaned_json) do
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

  defp convert_maps_to_json_strings(changeset) do
    changes = changeset.changes
    
    updated_changes = 
      changes
      |> convert_field_to_json_string("trigger_conditions")
      |> convert_field_to_json_string("actions")
    
    %{changeset | changes: updated_changes}
  end

  defp convert_field_to_json_string(changes, field_name) do
    field_atom = String.to_atom(field_name)
    
    case Map.get(changes, field_atom) do
      value when is_map(value) ->
        json_string = Jason.encode!(value, pretty: true)
        Map.put(changes, field_atom, json_string)
      
      _ ->
        changes
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

  defp clean_json(json_string) when is_binary(json_string) do
    json_string
    |> String.replace(~r/\n\s*/, "")  # Remove newlines and following whitespace
    |> String.replace(~r/\s+/, " ")   # Normalize remaining whitespace
    |> String.trim()
  end
end