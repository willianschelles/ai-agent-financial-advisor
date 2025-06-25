defmodule AiAgent.Google.CalendarAPI do
  @moduledoc """
  Google Calendar API client for creating and managing calendar events.

  This module provides a wrapper around Google Calendar API calls using OAuth2 authentication.
  """

  require Logger

  @base_url "https://www.googleapis.com/calendar/v3"
  @primary_calendar "primary"

  @doc """
  Create a new calendar event.

  ## Parameters
  - user: User struct with Google OAuth tokens
  - event_data: Map containing event details

  ## Returns
  - {:ok, event} on success
  - {:error, reason} on failure
  """
  def create_event(user, event_data) do
    Logger.info("Creating calendar event for user #{user.id}")

    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@base_url}/calendars/#{@primary_calendar}/events"

        headers = [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]

        IO.inspect(event_data, label: "Event Data")
        IO.inspect(access_token, label: "access_token ")
        Logger.debug("Sending calendar event creation request")

        case Req.post(url, headers: headers, json: event_data) do
          {:ok, %{status: 200, body: event}} ->
            Logger.info("Successfully created calendar event: #{event["id"]}")
            {:ok, event}

          {:ok, %{status: status, body: body}} ->
            Logger.error("Google Calendar API error: #{status} - #{inspect(body)}")
            {:error, "Calendar API error: #{status}"}

          {:error, reason} ->
            Logger.error("Failed to call Calendar API: #{inspect(reason)}")
            {:error, "Network error: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  List calendar events within a time range.

  ## Parameters
  - user: User struct with Google OAuth tokens
  - params: Query parameters for the API call

  ## Returns
  - {:ok, [events]} on success
  - {:error, reason} on failure
  """
  def list_events(user, params \\ %{}) do
    Logger.info("Listing calendar events for user #{user.id}")

    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@base_url}/calendars/#{@primary_calendar}/events"

        headers = [
          {"Authorization", "Bearer #{access_token}"}
        ]

        # Build query parameters
        query_params =
          params
          |> Map.take([:timeMin, :timeMax, :maxResults, :singleEvents, :orderBy])
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Enum.into(%{})

        Logger.debug("Fetching calendar events with params: #{inspect(query_params)}")

        case Req.get(url, headers: headers, params: query_params) do
          {:ok, %{status: 200, body: %{"items" => events}}} ->
            Logger.info("Retrieved #{length(events)} calendar events")
            {:ok, events}

          {:ok, %{status: 200, body: %{"items" => nil}}} ->
            {:ok, []}

          {:ok, %{status: status, body: body}} ->
            Logger.error("Google Calendar API error: #{status} - #{inspect(body)}")
            {:error, "Calendar API error: #{status}"}

          {:error, reason} ->
            Logger.error("Failed to call Calendar API: #{inspect(reason)}")
            {:error, "Network error: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Find free time slots for scheduling.

  ## Parameters
  - user: User struct with Google OAuth tokens
  - start_date: Date to start searching
  - end_date: Date to end searching
  - duration_minutes: Duration of the desired slot
  - business_hours_only: Whether to only search during business hours

  ## Returns
  - {:ok, [free_slots]} on success
  - {:error, reason} on failure
  """
  def find_free_time(user, start_date, end_date, duration_minutes, business_hours_only \\ true) do
    Logger.info("Finding free time slots for user #{user.id}")

    # Get busy times first
    case get_busy_times(user, start_date, end_date) do
      {:ok, busy_times} ->
        # Generate potential time slots
        potential_slots =
          generate_time_slots(start_date, end_date, duration_minutes, business_hours_only)

        # Filter out slots that conflict with busy times
        free_slots =
          Enum.reject(potential_slots, fn slot ->
            conflicts_with_busy_times?(slot, busy_times)
          end)

        Logger.info("Found #{length(free_slots)} free time slots")
        {:ok, free_slots}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Update an existing calendar event.

  ## Parameters
  - user: User struct with Google OAuth tokens
  - event_id: ID of the event to update
  - event_data: Updated event data

  ## Returns
  - {:ok, event} on success
  - {:error, reason} on failure
  """
  def update_event(user, event_id, event_data) do
    Logger.info("Updating calendar event #{event_id} for user #{user.id}")

    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@base_url}/calendars/#{@primary_calendar}/events/#{event_id}"

        headers = [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]

        case Req.patch(url, headers: headers, json: event_data) do
          {:ok, %{status: 200, body: event}} ->
            Logger.info("Successfully updated calendar event: #{event["id"]}")
            {:ok, event}

          {:ok, %{status: status, body: body}} ->
            Logger.error("Google Calendar API error: #{status} - #{inspect(body)}")
            {:error, "Calendar API error: #{status}"}

          {:error, reason} ->
            Logger.error("Failed to call Calendar API: #{inspect(reason)}")
            {:error, "Network error: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Delete a calendar event.

  ## Parameters
  - user: User struct with Google OAuth tokens
  - event_id: ID of the event to delete

  ## Returns
  - {:ok, :deleted} on success
  - {:error, reason} on failure
  """
  def delete_event(user, event_id) do
    Logger.info("Deleting calendar event #{event_id} for user #{user.id}")

    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@base_url}/calendars/#{@primary_calendar}/events/#{event_id}"

        headers = [
          {"Authorization", "Bearer #{access_token}"}
        ]

        case Req.delete(url, headers: headers) do
          {:ok, %{status: 204}} ->
            Logger.info("Successfully deleted calendar event: #{event_id}")
            {:ok, :deleted}

          {:ok, %{status: status, body: body}} ->
            Logger.error("Google Calendar API error: #{status} - #{inspect(body)}")
            {:error, "Calendar API error: #{status}"}

          {:error, reason} ->
            Logger.error("Failed to call Calendar API: #{inspect(reason)}")
            {:error, "Network error: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

  defp get_access_token(user) do
    case user.google_tokens do
      %{"access_token" => access_token} when is_binary(access_token) ->
        # TODO: Check if token is expired and refresh if needed
        {:ok, access_token}

      _ ->
        Logger.error("No valid Google access token found for user #{user.id}")
        {:error, "Google Calendar access not authorized"}
    end
  end

  defp get_busy_times(user, start_date, end_date) do
    # Convert dates to datetime strings
    start_datetime = "#{Date.to_iso8601(start_date)}T00:00:00Z"
    end_datetime = "#{Date.to_iso8601(end_date)}T23:59:59Z"

    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@base_url}/freeBusy"

        headers = [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]

        request_body = %{
          timeMin: start_datetime,
          timeMax: end_datetime,
          items: [%{id: @primary_calendar}]
        }

        case Req.post(url, headers: headers, json: request_body) do
          {:ok, %{status: 200, body: %{"calendars" => calendars}}} ->
            busy_times =
              calendars
              |> Map.get(@primary_calendar, %{})
              |> Map.get("busy", [])
              |> Enum.map(fn busy_period ->
                %{
                  start: busy_period["start"],
                  end: busy_period["end"]
                }
              end)

            {:ok, busy_times}

          {:ok, %{status: status, body: body}} ->
            Logger.error("Google Calendar FreeBusy API error: #{status} - #{inspect(body)}")
            {:error, "FreeBusy API error: #{status}"}

          {:error, reason} ->
            Logger.error("Failed to call FreeBusy API: #{inspect(reason)}")
            {:error, "Network error: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_time_slots(start_date, end_date, duration_minutes, business_hours_only) do
    # Generate 30-minute intervals during the specified date range
    current_date = start_date
    slots = []

    generate_slots_for_date_range(
      current_date,
      end_date,
      duration_minutes,
      business_hours_only,
      slots
    )
  end

  defp generate_slots_for_date_range(
         current_date,
         end_date,
         duration_minutes,
         business_hours_only,
         slots
       )
       when current_date <= end_date do
    day_slots = generate_slots_for_day(current_date, duration_minutes, business_hours_only)
    next_date = Date.add(current_date, 1)

    generate_slots_for_date_range(
      next_date,
      end_date,
      duration_minutes,
      business_hours_only,
      slots ++ day_slots
    )
  end

  defp generate_slots_for_date_range(_, _, _, _, slots), do: slots

  defp generate_slots_for_day(date, duration_minutes, business_hours_only) do
    # Define time range
    {start_hour, end_hour} =
      if business_hours_only do
        # 9 AM to 5 PM
        {9, 17}
      else
        # 8 AM to 8 PM
        {8, 20}
      end

    # Generate 30-minute slots
    # minutes
    slot_interval = 30
    slots_per_hour = div(60, slot_interval)
    total_slots = (end_hour - start_hour) * slots_per_hour

    0..(total_slots - 1)
    |> Enum.map(fn slot_index ->
      minutes_from_start = slot_index * slot_interval
      hour = start_hour + div(minutes_from_start, 60)
      minute = rem(minutes_from_start, 60)

      # Create start and end times
      start_time = DateTime.new!(date, Time.new!(hour, minute, 0), "Etc/UTC")
      end_time = DateTime.add(start_time, duration_minutes, :minute)

      %{
        start_time: DateTime.to_iso8601(start_time),
        end_time: DateTime.to_iso8601(end_time)
      }
    end)
    |> Enum.filter(fn slot ->
      # Only include slots that end before the day's end time
      {:ok, end_datetime, _} = DateTime.from_iso8601(slot.end_time)
      end_datetime.hour < end_hour
    end)
  end

  defp conflicts_with_busy_times?(slot, busy_times) do
    {:ok, slot_start, _} = DateTime.from_iso8601(slot.start_time)
    {:ok, slot_end, _} = DateTime.from_iso8601(slot.end_time)

    Enum.any?(busy_times, fn busy_time ->
      {:ok, busy_start, _} = DateTime.from_iso8601(busy_time.start)
      {:ok, busy_end, _} = DateTime.from_iso8601(busy_time.end)

      # Check for any overlap
      not (DateTime.compare(slot_end, busy_start) == :lt or
             DateTime.compare(slot_start, busy_end) == :gt)
    end)
  end
end
