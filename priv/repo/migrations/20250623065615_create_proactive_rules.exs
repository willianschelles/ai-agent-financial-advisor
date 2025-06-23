defmodule AiAgent.Repo.Migrations.CreateProactiveRules do
  use Ecto.Migration

  def change do
    create table(:proactive_rules) do
      add :name, :string
      add :description, :text
      add :trigger_type, :string
      add :trigger_conditions, :map
      add :actions, :map
      add :is_active, :boolean, default: false, null: false
      add :user_id, references(:users, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:proactive_rules, [:user_id])
  end
end
