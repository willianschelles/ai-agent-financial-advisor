defmodule AiAgent.Document do
  use Ecto.Schema
  import Ecto.Changeset

  schema "documents" do
    field :type, :string
    field :source, :string
    field :content, :string
    field :user_id, :id

    field :embedding, Pgvector.Ecto.Vector

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(document, attrs) do
    document
    |> cast(attrs, [:type, :source, :content, :user_id, :embedding])
    |> validate_required([:type, :source, :content, :user_id])
  end
end
