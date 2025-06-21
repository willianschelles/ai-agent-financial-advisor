defmodule AiAgent.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string
      add :google_tokens, :map
      add :hubspot_tokens, :map

      timestamps(type: :utc_datetime)
    end
  end
end
