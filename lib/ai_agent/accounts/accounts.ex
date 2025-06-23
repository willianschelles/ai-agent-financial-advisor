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
    IO.inspect(creds, label: "HubSpot Credentials")
    IO.inspect(creds.token, label: "HubSpot Access Token")
    token = Jason.decode!(creds.token)
    IO.inspect(token, label: "Decoded HubSpot Access Token")

    tokens = %{
      access_token: token["access_token"],
      token_type: token["token_type"],
      refresh_token: token["refresh_token"],
      expires_in: token["expires_in"]
    }

    user
    |> User.changeset(%{hubspot_tokens: tokens})
    |> Repo.update()
  end

  def disconnect_hubspot(user) do
    user
    |> User.changeset(%{hubspot_tokens: nil})
    |> Repo.update()
  end

  def update_google_tokens(user, new_tokens) do
    user
    |> User.changeset(%{google_tokens: new_tokens})
    |> Repo.update()
  end

  def get_user!(id) do
    Repo.get!(User, id)
  end
end
