defmodule AiAgent.Accounts do
  alias AiAgent.Repo
  alias AiAgent.Schemas.User

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
end
