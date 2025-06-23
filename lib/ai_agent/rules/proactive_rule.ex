defmodule AiAgent.Rules.ProactiveRule do
  use Ecto.Schema
  import Ecto.Changeset

  @trigger_types ["email_received", "calendar_event", "hubspot_contact_created", "hubspot_note_created"]

  schema "proactive_rules" do
    field :name, :string
    field :description, :string
    field :trigger_type, :string
    field :trigger_conditions, :map
    field :actions, :map
    field :is_active, :boolean, default: false
    
    belongs_to :user, AiAgent.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(proactive_rule, attrs) do
    proactive_rule
    |> cast(attrs, [:name, :description, :trigger_type, :trigger_conditions, :actions, :is_active, :user_id])
    |> validate_required([:name, :description, :trigger_type, :user_id])
    |> validate_inclusion(:trigger_type, @trigger_types)
    |> validate_trigger_conditions()
    |> validate_actions()
  end

  defp validate_trigger_conditions(changeset) do
    case get_field(changeset, :trigger_type) do
      "email_received" ->
        validate_email_conditions(changeset)
      "calendar_event" ->
        validate_calendar_conditions(changeset)
      "hubspot_contact_created" ->
        validate_hubspot_contact_conditions(changeset)
      "hubspot_note_created" ->
        validate_hubspot_note_conditions(changeset)
      _ ->
        changeset
    end
  end

  defp validate_email_conditions(changeset) do
    case get_field(changeset, :trigger_conditions) do
      conditions when is_map(conditions) ->
        changeset
      conditions when is_binary(conditions) ->
        case Jason.decode(conditions) do
          {:ok, _} -> 
            add_error(changeset, :trigger_conditions, "JSON was not properly parsed for email triggers")
          {:error, %Jason.DecodeError{} = error} ->
            add_error(changeset, :trigger_conditions, "Invalid JSON for email triggers: #{Exception.message(error)}")
        end
      _ ->
        add_error(changeset, :trigger_conditions, "must be a valid JSON object for email triggers")
    end
  end

  defp validate_calendar_conditions(changeset) do
    case get_field(changeset, :trigger_conditions) do
      conditions when is_map(conditions) ->
        changeset
      conditions when is_binary(conditions) ->
        add_error(changeset, :trigger_conditions, "invalid JSON format for calendar triggers")
      _ ->
        add_error(changeset, :trigger_conditions, "must be a valid JSON object for calendar triggers")
    end
  end

  defp validate_hubspot_contact_conditions(changeset) do
    case get_field(changeset, :trigger_conditions) do
      conditions when is_map(conditions) ->
        changeset
      conditions when is_binary(conditions) ->
        add_error(changeset, :trigger_conditions, "invalid JSON format for HubSpot contact triggers")
      _ ->
        add_error(changeset, :trigger_conditions, "must be a valid JSON object for HubSpot contact triggers")
    end
  end

  defp validate_hubspot_note_conditions(changeset) do
    case get_field(changeset, :trigger_conditions) do
      conditions when is_map(conditions) ->
        changeset
      conditions when is_binary(conditions) ->
        add_error(changeset, :trigger_conditions, "invalid JSON format for HubSpot note triggers")
      _ ->
        add_error(changeset, :trigger_conditions, "must be a valid JSON object for HubSpot note triggers")
    end
  end

  defp validate_actions(changeset) do
    case get_field(changeset, :actions) do
      actions when is_map(actions) and map_size(actions) > 0 ->
        changeset
      actions when is_map(actions) ->
        add_error(changeset, :actions, "must contain at least one action")
      actions when is_binary(actions) ->
        # Try to parse and give specific error
        case Jason.decode(actions) do
          {:ok, _} -> 
            # JSON is valid but wasn't parsed - shouldn't happen
            add_error(changeset, :actions, "JSON was not properly parsed")
          {:error, %Jason.DecodeError{} = error} ->
            add_error(changeset, :actions, "Invalid JSON: #{Exception.message(error)}")
        end
      _ ->
        add_error(changeset, :actions, "must be a valid JSON object")
    end
  end

  def trigger_types, do: @trigger_types
end
