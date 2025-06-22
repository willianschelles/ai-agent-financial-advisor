defmodule AiAgent.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents) do
      add :type, :string
      add :source, :string
      add :content, :text
      add :user_id, references(:users, on_delete: :nothing)
      add :embedding, :vector, size: 1536

      timestamps(type: :utc_datetime)
    end

    create index(:documents, [:user_id])
  end
end
