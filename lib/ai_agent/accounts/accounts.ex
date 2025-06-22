defmodule AiAgent.Accounts do
  alias AiAgent.Repo
  alias AiAgent.User

  def upsert_user_from_auth(%Ueberauth.Auth{info: info, credentials: creds}) do
    email = info.email

    google_tokens = %{
      access_token: creds.token,
      refresh_token: creds.refresh_token
    }

    case Repo.get_by(User, email: email) do
      nil ->
        %User{email: email, google_tokens: google_tokens}
        |> Repo.insert()
        |> case do
          {:ok, user} -> {:ok, user}
          error -> error
        end

      user ->
        user
        |> Ecto.Changeset.change(google_tokens: google_tokens)
        |> Repo.update()
    end
  end

  def connect_hubspot(user, %Ueberauth.Auth{credentials: creds}) do
    tokens = %{
      access_token: creds.token,
      refresh_token: creds.refresh_token,
      expires_at: creds.expires_at
    }

    user
    |> User.changeset(%{hubspot_tokens: tokens})
    |> Repo.update()
  end

  def get_user!(id) do
    Repo.get!(User, id)
  end
end
