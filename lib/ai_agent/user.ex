defmodule AiAgent.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :google_tokens, :map
    field :hubspot_tokens, :map

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :google_tokens, :hubspot_tokens])
    |> validate_required([:email])
  end
end
