defmodule AiAgent.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "pending"
      add :priority, :string, null: false, default: "medium"
      add :task_type, :string, null: false
      add :original_request, :text, null: false
      add :context_data, :map, null: false, default: %{}
      add :workflow_state, :map, null: false, default: %{}
      add :steps_completed, {:array, :string}, default: []
      add :next_step, :string
      add :waiting_for, :string
      add :waiting_for_data, :map, default: %{}
      add :parent_task_id, references(:tasks, on_delete: :delete_all)
      add :scheduled_for, :utc_datetime
      add :completed_at, :utc_datetime
      add :failed_at, :utc_datetime
      add :failure_reason, :text
      add :retry_count, :integer, default: 0
      add :max_retries, :integer, default: 3
      add :last_activity_at, :utc_datetime
      add :metadata, :map, default: %{}

      timestamps()
    end

    create index(:tasks, [:user_id])
    create index(:tasks, [:status])
    create index(:tasks, [:task_type])
    create index(:tasks, [:parent_task_id])
    create index(:tasks, [:waiting_for])
    create index(:tasks, [:scheduled_for])
    create index(:tasks, [:last_activity_at])
    create index(:tasks, [:user_id, :status])
  end
end