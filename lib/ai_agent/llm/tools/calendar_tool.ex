defmodule AiAgent.LLM.Tools.CalendarTool do
  @moduledoc """
  Google Calendar integration tool for scheduling and managing appointments.

  This tool allows the AI to:
  - Create calendar events/appointments
  - List upcoming events
  - Update existing events
  - Delete/cancel events
  - Find available time slots

  Uses Google Calendar API with OAuth2 authentication.
  """

  require Logger

  alias AiAgent.Google.CalendarAPI
  alias AiAgent.User

  @doc """
  Get the OpenAI function calling schema for calendar operations.

  Returns the function definitions that OpenAI can use to call calendar actions.
  """
  def get_tool_schema do
    [
      %{
        type: "function",
        function: %{
          name: "calendar_create_event",
          description: "Create a new calendar event/appointment",
          parameters: %{
            type: "object",
            properties: %{
              title: %{
                type: "string",
                description: "Title/subject of the event"
              },
              description: %{
                type: "string",
                description: "Optional description or notes for the event"
              },
              start_time: %{
                type: "string",
                description: "Start time in ISO 8601 format (e.g., '2024-01-15T14:00:00-05:00')"
              },
              end_time: %{
                type: "string",
                description: "End time in ISO 8601 format (e.g., '2024-01-15T15:00:00-05:00')"
              },
              attendees: %{
                type: "array",
                items: %{type: "string"},
                description: "List of email addresses to invite (optional)"
              },
              location: %{
                type: "string",
                description: "Meeting location (optional)"
              }
            },
            required: ["title", "start_time", "end_time"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "calendar_list_events",
          description: "List upcoming calendar events",
          parameters: %{
            type: "object",
            properties: %{
              time_min: %{
                type: "string",
                description:
                  "Start time for search in ISO 8601 format (optional, defaults to now)"
              },
              time_max: %{
                type: "string",
                description:
                  "End time for search in ISO 8601 format (optional, defaults to 7 days from now)"
              },
              max_results: %{
                type: "integer",
                description: "Maximum number of events to return (optional, defaults to 10)"
              }
            },
            required: []
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "calendar_find_free_time",
          description: "Find available time slots for scheduling",
          parameters: %{
            type: "object",
            properties: %{
              start_date: %{
                type: "string",
                description: "Start date to search for free time (YYYY-MM-DD format)"
              },
              end_date: %{
                type: "string",
                description: "End date to search for free time (YYYY-MM-DD format)"
              },
              duration_minutes: %{
                type: "integer",
                description: "Duration of the meeting in minutes"
              },
              business_hours_only: %{
                type: "boolean",
                description:
                  "Only search during business hours (9 AM - 5 PM) (optional, defaults to true)"
              }
            },
            required: ["start_date", "end_date", "duration_minutes"]
          }
        }
      }
    ]
  end

  @doc """
  Execute a calendar tool function.

  ## Parameters
  - user: User struct with Google OAuth tokens
  - function_name: Name of the function to execute
  - arguments: Map of arguments for the function

  ## Returns
  - {:ok, result} on success
  - {:error, reason} on failure
  """
  def execute(user, function_name, arguments) do
    Logger.info("Executing calendar function: #{function_name}")

    case function_name do
      "calendar_create_event" ->
        create_event(user, arguments)

      "calendar_list_events" ->
        list_events(user, arguments)

      "calendar_find_free_time" ->
        find_free_time(user, arguments)

      _ ->
        Logger.error("Unknown calendar function: #{function_name}")
        {:error, "Unknown calendar function: #{function_name}"}
    end
  end

  # Private functions for each calendar action

  defp create_event(user, args) do
    Logger.info("Creating calendar event for user #{user.id}")

    # Validate required arguments
    with {:ok, title} <- get_required_arg(args, "title"),
         {:ok, start_time} <- get_required_arg(args, "start_time"),
         {:ok, end_time} <- get_required_arg(args, "end_time") do
      # Build event data
      event_data = %{
        summary: title,
        description: Map.get(args, "description", ""),
        start: %{
          dateTime: start_time,
          # TODO: Get from user preferences
          timeZone: "America/New_York"
        },
        end: %{
          dateTime: end_time,
          timeZone: "America/New_York"
        }
      }

      # Add optional fields
      event_data =
        event_data
        |> maybe_add_location(args)
        |> maybe_add_attendees(args)

      # Call Google Calendar API
      case CalendarAPI.create_event(user, event_data) do
        {:ok, event} ->
          Logger.info("Successfully created calendar event: #{event["id"]}")

          {:ok,
           %{
             event_id: event["id"],
             title: event["summary"],
             start_time: event["start"]["dateTime"],
             end_time: event["end"]["dateTime"],
             html_link: event["htmlLink"],
             message: "Event '#{event["summary"]}' created successfully"
           }}

        {:error, reason} ->
          Logger.error("Failed to create calendar event: #{inspect(reason)}")
          {:error, "Failed to create calendar event: #{reason}"}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_events(user, args) do
    Logger.info("Listing calendar events for user #{user.id}")

    # Set default time range (now to 7 days from now)
    now = DateTime.utc_now()
    week_from_now = DateTime.add(now, 7, :day)

    params = %{
      timeMin: Map.get(args, "time_min", DateTime.to_iso8601(now)),
      timeMax: Map.get(args, "time_max", DateTime.to_iso8601(week_from_now)),
      maxResults: Map.get(args, "max_results", 10),
      singleEvents: true,
      orderBy: "startTime"
    }

    case CalendarAPI.list_events(user, params) do
      {:ok, events} ->
        Logger.info("Retrieved #{length(events)} calendar events")

        formatted_events =
          Enum.map(events, fn event ->
            %{
              id: event["id"],
              title: event["summary"] || "No title",
              start_time: get_event_time(event, "start"),
              end_time: get_event_time(event, "end"),
              location: Map.get(event, "location"),
              attendees: format_attendees(event["attendees"]),
              html_link: event["htmlLink"]
            }
          end)

        {:ok,
         %{
           events: formatted_events,
           count: length(formatted_events),
           message: "Found #{length(formatted_events)} upcoming events"
         }}

      {:error, reason} ->
        Logger.error("Failed to list calendar events: #{inspect(reason)}")
        {:error, "Failed to retrieve calendar events: #{reason}"}
    end
  end

  defp find_free_time(user, args) do
    Logger.info("Finding free time slots for user #{user.id}")

    with {:ok, start_date} <- get_required_arg(args, "start_date"),
         {:ok, end_date} <- get_required_arg(args, "end_date"),
         {:ok, duration} <- get_required_arg(args, "duration_minutes") do
      business_hours_only = Map.get(args, "business_hours_only", true)

      # Parse dates
      case {Date.from_iso8601(start_date), Date.from_iso8601(end_date)} do
        {{:ok, start_date_parsed}, {:ok, end_date_parsed}} ->
          # Find free time slots
          case CalendarAPI.find_free_time(
                 user,
                 start_date_parsed,
                 end_date_parsed,
                 duration,
                 business_hours_only
               ) do
            {:ok, free_slots} ->
              Logger.info("Found #{length(free_slots)} free time slots")

              formatted_slots =
                Enum.map(free_slots, fn slot ->
                  %{
                    start_time: slot.start_time,
                    end_time: slot.end_time,
                    duration_minutes: duration
                  }
                end)

              {:ok,
               %{
                 free_slots: formatted_slots,
                 count: length(formatted_slots),
                 message:
                   "Found #{length(formatted_slots)} available time slots of #{duration} minutes"
               }}

            {:error, reason} ->
              Logger.error("Failed to find free time: #{inspect(reason)}")
              {:error, "Failed to find available time slots: #{reason}"}
          end

        _ ->
          {:error, "Invalid date format. Use YYYY-MM-DD format."}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper functions

  defp get_required_arg(args, key) do
    case Map.get(args, key) do
      nil -> {:error, "Missing required argument: #{key}"}
      value -> {:ok, value}
    end
  end

  defp maybe_add_location(event_data, args) do
    case Map.get(args, "location") do
      nil -> event_data
      location -> Map.put(event_data, :location, location)
    end
  end

  defp maybe_add_attendees(event_data, args) do
    case Map.get(args, "attendees") do
      nil ->
        event_data

      attendees when is_list(attendees) ->
        attendee_list =
          Enum.map(attendees, fn email ->
            %{email: email}
          end)

        Map.put(event_data, :attendees, attendee_list)

      _ ->
        event_data
    end
  end

  defp get_event_time(event, field) do
    case get_in(event, [field, "dateTime"]) do
      nil -> get_in(event, [field, "date"])
      datetime -> datetime
    end
  end

  defp format_attendees(nil), do: []

  defp format_attendees(attendees) when is_list(attendees) do
    Enum.map(attendees, fn attendee ->
      %{
        email: attendee["email"],
        name: Map.get(attendee, "displayName"),
        response_status: Map.get(attendee, "responseStatus", "needsAction")
      }
    end)
  end

  defp format_attendees(_), do: []
end
