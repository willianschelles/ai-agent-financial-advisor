defmodule AiAgent.Task do
  @moduledoc """
  Schema for persistent task storage and multi-step workflow management.
  
  Tasks represent user requests that may require multiple steps, external waiting periods,
  and complex workflows. This enables the AI to maintain state across sessions and 
  resume work when external events occur.
  """
  
  use Ecto.Schema
  import Ecto.Changeset
  
  alias AiAgent.User
  
  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :id
  
  # Task statuses
  @valid_statuses ~w(pending in_progress waiting_for_response completed failed paused cancelled)
  
  # Task priorities
  @valid_priorities ~w(low medium high urgent)
  
  # Task types
  @valid_task_types ~w(
    email_workflow
    calendar_workflow
    hubspot_workflow
    email_calendar_workflow
    multi_step_action
    scheduled_task
    recurring_task
    follow_up_task
    composite_task
  )
  
  # What tasks can wait for
  @valid_waiting_for ~w(
    email_reply
    calendar_response
    external_approval
    scheduled_time
    user_input
    api_response
    webhook_event
    manual_completion
  )
  
  schema "tasks" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "pending"
    field :priority, :string, default: "medium"
    field :task_type, :string
    field :original_request, :string
    field :context_data, :map, default: %{}
    field :workflow_state, :map, default: %{}
    field :steps_completed, {:array, :string}, default: []
    field :next_step, :string
    field :waiting_for, :string
    field :waiting_for_data, :map, default: %{}
    field :scheduled_for, :utc_datetime
    field :completed_at, :utc_datetime
    field :failed_at, :utc_datetime
    field :failure_reason, :string
    field :retry_count, :integer, default: 0
    field :max_retries, :integer, default: 3
    field :last_activity_at, :utc_datetime
    field :metadata, :map, default: %{}
    
    belongs_to :user, User
    belongs_to :parent_task, __MODULE__
    has_many :subtasks, __MODULE__, foreign_key: :parent_task_id
    
    timestamps()
  end
  
  @doc """
  Creates a changeset for a task.
  """
  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :title, :description, :status, :priority, :task_type, :original_request,
      :context_data, :workflow_state, :steps_completed, :next_step, :waiting_for,
      :waiting_for_data, :user_id, :parent_task_id, :scheduled_for, :completed_at,
      :failed_at, :failure_reason, :retry_count, :max_retries, :last_activity_at,
      :metadata
    ])
    |> validate_required([:title, :status, :priority, :task_type, :original_request, :user_id])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:priority, @valid_priorities)
    |> validate_inclusion(:task_type, @valid_task_types)
    |> validate_inclusion(:waiting_for, @valid_waiting_for, allow_nil: true)
    |> validate_number(:retry_count, greater_than_or_equal_to: 0)
    |> validate_number(:max_retries, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:parent_task_id)
    |> put_last_activity()
  end
  
  @doc """
  Changeset for updating task status.
  """
  def status_changeset(task, status, attrs \\ %{}) do
    base_attrs = Map.put(attrs, :status, status)
    
    # Add completion timestamp if completed
    attrs_with_timestamp = case status do
      "completed" -> Map.put(base_attrs, :completed_at, DateTime.utc_now() |> DateTime.truncate(:second))
      "failed" -> Map.put(base_attrs, :failed_at, DateTime.utc_now() |> DateTime.truncate(:second))
      _ -> base_attrs
    end
    
    changeset(task, attrs_with_timestamp)
  end
  
  @doc """
  Changeset for updating workflow state.
  """
  def workflow_changeset(task, workflow_state, next_step \\ nil) do
    attrs = %{
      workflow_state: workflow_state,
      next_step: next_step
    }
    
    changeset(task, attrs)
  end
  
  @doc """
  Changeset for marking a task as waiting for external response.
  """
  def waiting_changeset(task, waiting_for, waiting_data \\ %{}) do
    attrs = %{
      status: "waiting_for_response",
      waiting_for: waiting_for,
      waiting_for_data: waiting_data
    }
    
    changeset(task, attrs)
  end
  
  @doc """
  Changeset for resuming a waiting task.
  """
  def resume_changeset(task, new_status \\ "in_progress") do
    attrs = %{
      status: new_status,
      waiting_for: nil,
      waiting_for_data: %{}
    }
    
    changeset(task, attrs)
  end
  
  @doc """
  Changeset for adding a completed step.
  """
  def add_step_changeset(task, step_name) do
    new_steps = [step_name | task.steps_completed] |> Enum.uniq()
    changeset(task, %{steps_completed: new_steps})
  end
  
  @doc """
  Changeset for incrementing retry count.
  """
  def retry_changeset(task) do
    changeset(task, %{retry_count: task.retry_count + 1})
  end
  
  @doc """
  Get all valid statuses.
  """
  def valid_statuses, do: @valid_statuses
  
  @doc """
  Get all valid priorities.
  """
  def valid_priorities, do: @valid_priorities
  
  @doc """
  Get all valid task types.
  """
  def valid_task_types, do: @valid_task_types
  
  @doc """
  Get all valid waiting_for values.
  """
  def valid_waiting_for, do: @valid_waiting_for
  
  @doc """
  Check if task is active (can be worked on).
  """
  def active?(%__MODULE__{status: status}) do
    status in ~w(pending in_progress)
  end
  
  @doc """
  Check if task is waiting for external input.
  """
  def waiting?(%__MODULE__{status: "waiting_for_response"}), do: true
  def waiting?(_), do: false
  
  @doc """
  Check if task is completed.
  """
  def completed?(%__MODULE__{status: status}) do
    status in ~w(completed cancelled)
  end
  
  @doc """
  Check if task has failed.
  """
  def failed?(%__MODULE__{status: "failed"}), do: true
  def failed?(_), do: false
  
  @doc """
  Check if task can be retried.
  """
  def can_retry?(%__MODULE__{retry_count: count, max_retries: max}) do
    count < max
  end
  
  @doc """
  Check if task is overdue (past scheduled time and not completed).
  """
  def overdue?(%__MODULE__{scheduled_for: nil}), do: false
  def overdue?(%__MODULE__{status: status}) when status in ~w(completed cancelled), do: false
  def overdue?(%__MODULE__{scheduled_for: scheduled_for}) do
    DateTime.compare(DateTime.utc_now() |> DateTime.truncate(:second), scheduled_for) == :gt
  end
  
  # Private helpers
  
  defp put_last_activity(changeset) do
    put_change(changeset, :last_activity_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end