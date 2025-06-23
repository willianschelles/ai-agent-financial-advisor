defmodule AiAgent.TaskManager do
  @moduledoc """
  Task lifecycle management for persistent multi-step workflows.

  This module handles creating, updating, monitoring, and resuming tasks that may
  span multiple sessions and require waiting for external events like email replies
  or calendar responses.
  """

  require Logger

  import Ecto.Query
  alias AiAgent.{Repo, Task, User}

  @doc """
  Create a new task from a user request.

  ## Parameters
  - user: User struct
  - request: Original user request text
  - task_type: Type of task being created
  - opts: Additional options including:
    - :title - Task title (auto-generated if not provided)
    - :description - Task description
    - :priority - Task priority (low, medium, high, urgent)
    - :context_data - Additional context for the task
    - :scheduled_for - When to execute the task
    - :parent_task_id - ID of parent task if this is a subtask

  ## Returns
  - {:ok, task} on success
  - {:error, changeset} on failure
  """
  def create_task(user, request, task_type, opts \\ %{}) do
    Logger.info("Creating task for user #{user.id}: #{task_type}")

    title = Map.get(opts, :title, generate_title(request, task_type))

    attrs = %{
      user_id: user.id,
      title: title,
      description: Map.get(opts, :description),
      priority: Map.get(opts, :priority, "medium"),
      task_type: task_type,
      original_request: request,
      context_data: Map.get(opts, :context_data, %{}),
      scheduled_for: Map.get(opts, :scheduled_for),
      parent_task_id: Map.get(opts, :parent_task_id),
      metadata: Map.get(opts, :metadata, %{})
    }

    case %Task{} |> Task.changeset(attrs) |> Repo.insert() do
      {:ok, task} ->
        Logger.info("Successfully created task #{task.id}")
        {:ok, task}

      {:error, changeset} ->
        Logger.error("Failed to create task: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Update task status and workflow state.

  ## Parameters
  - task_id: ID of the task to update
  - status: New status for the task
  - opts: Additional options including:
    - :workflow_state - Updated workflow state
    - :next_step - Next step to execute
    - :failure_reason - Reason for failure (if status is "failed")
    - :metadata - Additional metadata

  ## Returns
  - {:ok, task} on success
  - {:error, reason} on failure
  """
  def update_task_status(task_id, status, opts \\ %{}) do
    Logger.info("Updating task #{task_id} status to #{status}")

    case get_task(task_id) do
      {:ok, task} ->
        attrs = opts
        |> Map.put(:status, status)
        |> maybe_add_failure_reason(status)

        changeset = Task.status_changeset(task, status, attrs)

        case Repo.update(changeset) do
          {:ok, updated_task} ->
            Logger.info("Successfully updated task #{task_id}")
            maybe_update_parent_task(updated_task)
            {:ok, updated_task}

          {:error, changeset} ->
            Logger.error("Failed to update task #{task_id}: #{inspect(changeset.errors)}")
            {:error, changeset}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Mark a task as waiting for external response.

  ## Parameters
  - task_id: ID of the task
  - waiting_for: What the task is waiting for (email_reply, calendar_response, etc.)
  - waiting_data: Additional data about what we're waiting for

  ## Returns
  - {:ok, task} on success
  - {:error, reason} on failure
  """
  def mark_task_waiting(task_id, waiting_for, waiting_data \\ %{}) do
    Logger.info("Marking task #{task_id} as waiting for #{waiting_for}")

    case get_task(task_id) do
      {:ok, task} ->
        changeset = Task.waiting_changeset(task, waiting_for, waiting_data)

        case Repo.update(changeset) do
          {:ok, updated_task} ->
            Logger.info("Successfully marked task #{task_id} as waiting")
            {:ok, updated_task}

          {:error, changeset} ->
            Logger.error("Failed to mark task #{task_id} as waiting: #{inspect(changeset.errors)}")
            {:error, changeset}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Resume a waiting task when the external event occurs.

  ## Parameters
  - task_id: ID of the task to resume
  - event_data: Data from the external event that triggered resumption
  - new_status: Status to set when resuming (default: "in_progress")

  ## Returns
  - {:ok, task} on success
  - {:error, reason} on failure
  """
  def resume_task(task_id, event_data \\ %{}, new_status \\ "in_progress") do
    Logger.info("Resuming task #{task_id} with status #{new_status}")

    case get_task(task_id) do
      {:ok, task} ->
        if Task.waiting?(task) do
          # Update workflow state with the event data
          updated_workflow_state = Map.merge(task.workflow_state, %{
            "last_event" => event_data,
            "resumed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          })

          attrs = %{
            workflow_state: updated_workflow_state
          }

          changeset = Task.resume_changeset(task, new_status)
          |> Task.changeset(attrs)

          case Repo.update(changeset) do
            {:ok, updated_task} ->
              Logger.info("Successfully resumed task #{task_id}")
              {:ok, updated_task}

            {:error, changeset} ->
              Logger.error("Failed to resume task #{task_id}: #{inspect(changeset.errors)}")
              {:error, changeset}
          end
        else
          Logger.warn("Attempted to resume non-waiting task #{task_id}")
          {:error, "Task is not waiting for external event"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Add a completed step to a task.

  ## Parameters
  - task_id: ID of the task
  - step_name: Name of the completed step
  - step_data: Optional data about the completed step

  ## Returns
  - {:ok, task} on success
  - {:error, reason} on failure
  """
  def add_completed_step(task_id, step_name, step_data \\ %{}) do
    Logger.info("Adding completed step '#{step_name}' to task #{task_id}")

    case get_task(task_id) do
      {:ok, task} ->
        # Update workflow state with step data
        updated_workflow_state = Map.put(task.workflow_state, "step_#{step_name}", step_data)

        changeset = Task.add_step_changeset(task, step_name)
        |> Task.changeset(%{workflow_state: updated_workflow_state})

        case Repo.update(changeset) do
          {:ok, updated_task} ->
            Logger.info("Successfully added step '#{step_name}' to task #{task_id}")
            {:ok, updated_task}

          {:error, changeset} ->
            Logger.error("Failed to add step to task #{task_id}: #{inspect(changeset.errors)}")
            {:error, changeset}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get a task by ID.

  ## Returns
  - {:ok, task} if found
  - {:error, :not_found} if not found
  """
  def get_task(task_id) do
    case Repo.get(Task, task_id) do
      nil -> {:error, :not_found}
      task -> {:ok, task}
    end
  end

  @doc """
  Get tasks for a user with optional filters.

  ## Parameters
  - user: User struct or user_id
  - opts: Filter options including:
    - :status - Filter by status
    - :task_type - Filter by task type
    - :waiting_for - Filter by what task is waiting for
    - :limit - Maximum number of results
    - :include_subtasks - Whether to include subtasks (default: true)

  ## Returns
  - List of tasks
  """
  def get_user_tasks(user, opts \\ %{}) do
    user_id = get_user_id(user)

    query = from(t in Task,
      where: t.user_id == ^user_id,
      order_by: [desc: t.last_activity_at]
    )

    query = apply_task_filters(query, opts)

    limit = Map.get(opts, :limit, 50)

    Repo.all(from(q in query, limit: ^limit))
  end

  @doc """
  Get active tasks (pending or in_progress) for a user.
  """
  def get_active_tasks(user) do
    get_user_tasks(user, %{status: ["pending", "in_progress"]})
  end

  @doc """
  Get tasks waiting for external events.

  ## Parameters
  - user: User struct or user_id (optional)
  - waiting_for: Specific type of external event (optional)

  ## Returns
  - List of waiting tasks
  """
  def get_waiting_tasks(user_id, waiting_for \\ nil) do
    query = from(t in Task,
      where: t.status == "waiting_for_response" and t.user_id == ^user_id,
      order_by: [asc: t.inserted_at]
    )

    query = if waiting_for do
      from(t in query, where: t.waiting_for == ^waiting_for)
    else
      query
    end

    Repo.all(query)
  end

  @doc """
  Get overdue tasks that should have been completed by now.
  """
  def get_overdue_tasks(user \\ nil) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    query = from(t in Task,
      where: not is_nil(t.scheduled_for) and t.scheduled_for < ^now,
      where: t.status not in ["completed", "cancelled", "failed"],
      order_by: [asc: t.scheduled_for]
    )

    query = if user do
      user_id = get_user_id(user)
      from(t in query, where: t.user_id == ^user_id)
    else
      query
    end

    Repo.all(query)
  end

  @doc """
  Retry a failed task if it hasn't exceeded max retries.

  ## Returns
  - {:ok, task} if retry was successful
  - {:error, reason} if retry not possible or failed
  """
  def retry_task(task_id) do
    case get_task(task_id) do
      {:ok, task} ->
        if Task.failed?(task) and Task.can_retry?(task) do
          changeset = Task.retry_changeset(task)
          |> Task.status_changeset("pending")

          case Repo.update(changeset) do
            {:ok, updated_task} ->
              Logger.info("Successfully retried task #{task_id}")
              {:ok, updated_task}

            {:error, changeset} ->
              Logger.error("Failed to retry task #{task_id}: #{inspect(changeset.errors)}")
              {:error, changeset}
          end
        else
          {:error, "Task cannot be retried"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Cancel a task and all its subtasks.
  """
  def cancel_task(task_id, reason \\ "Cancelled by user") do
    Logger.info("Cancelling task #{task_id}")

    case get_task(task_id) do
      {:ok, task} ->
        # Cancel all subtasks first
        subtasks = from(t in Task, where: t.parent_task_id == ^task_id) |> Repo.all()

        Enum.each(subtasks, fn subtask ->
          update_task_status(subtask.id, "cancelled", %{failure_reason: "Parent task cancelled"})
        end)

        # Cancel the main task
        update_task_status(task_id, "cancelled", %{failure_reason: reason})

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get task statistics for a user.
  """
  def get_task_stats(user) do
    user_id = get_user_id(user)

    stats_query = from(t in Task,
      where: t.user_id == ^user_id,
      group_by: t.status,
      select: {t.status, count(t.id)}
    )

    status_counts = Repo.all(stats_query) |> Map.new()

    total = Enum.sum(Map.values(status_counts))

    %{
      total: total,
      by_status: status_counts,
      active: Map.get(status_counts, "pending", 0) + Map.get(status_counts, "in_progress", 0),
      waiting: Map.get(status_counts, "waiting_for_response", 0),
      completed: Map.get(status_counts, "completed", 0),
      failed: Map.get(status_counts, "failed", 0)
    }
  end

  # Private helper functions

  defp get_user_id(%{id: id}), do: id
  defp get_user_id(user_id) when is_integer(user_id), do: user_id

  defp generate_title(request, task_type) do
    case task_type do
      "email_workflow" -> "Email: #{String.slice(request, 0, 50)}..."
      "calendar_workflow" -> "Calendar: #{String.slice(request, 0, 50)}..."
      "hubspot_workflow" -> "CRM: #{String.slice(request, 0, 50)}..."
      "multi_step_action" -> "Multi-step: #{String.slice(request, 0, 50)}..."
      _ -> "Task: #{String.slice(request, 0, 50)}..."
    end
  end

  defp maybe_add_failure_reason(attrs, "failed") do
    if not Map.has_key?(attrs, :failure_reason) do
      Map.put(attrs, :failure_reason, "Task failed during execution")
    else
      attrs
    end
  end
  defp maybe_add_failure_reason(attrs, _), do: attrs

  defp maybe_update_parent_task(%Task{parent_task_id: nil}), do: :ok
  defp maybe_update_parent_task(%Task{parent_task_id: parent_id, status: "completed"}) do
    # Check if all subtasks are completed, and if so, complete the parent
    incomplete_subtasks = from(t in Task,
      where: t.parent_task_id == ^parent_id and t.status not in ["completed", "cancelled", "failed"]
    ) |> Repo.all()

    if Enum.empty?(incomplete_subtasks) do
      update_task_status(parent_id, "completed", %{})
    end
  end
  defp maybe_update_parent_task(_), do: :ok

  defp apply_task_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:status, status}, q when is_binary(status) ->
        from(t in q, where: t.status == ^status)

      {:status, statuses}, q when is_list(statuses) ->
        from(t in q, where: t.status in ^statuses)

      {:task_type, task_type}, q ->
        from(t in q, where: t.task_type == ^task_type)

      {:waiting_for, waiting_for}, q ->
        from(t in q, where: t.waiting_for == ^waiting_for)

      {:include_subtasks, false}, q ->
        from(t in q, where: is_nil(t.parent_task_id))

      {_key, _value}, q ->
        q
    end)
  end
end
