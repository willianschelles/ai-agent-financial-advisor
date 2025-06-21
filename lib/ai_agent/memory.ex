defmodule AiAgent.Memory do
  use Ecto.Schema
  import Ecto.Changeset

  schema "memories" do
    field :instruction, :string
    field :user_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [:instruction])
    |> validate_required([:instruction])
  end
end
