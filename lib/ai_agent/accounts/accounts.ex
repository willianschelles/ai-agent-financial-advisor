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

  def create_user_with_hubspot(user_data) do
    %User{}
    |> User.changeset(user_data)
    |> Repo.insert()
  end

  def get_user!(id) do
    Repo.get!(User, id)
  end

  def get_user_by_email(email) do
    Repo.get_by(User, email: email)
  end

  def upsert_hubspot_tokens(user_id, tokens) when is_integer(user_id) do
    IO.inspect(user_id, label: "\n\nupsert_hubspot_tokens user_id")
    IO.inspect(tokens, label: "upsert_hubspot_tokens tokens\n\n")
    
    case Repo.get(User, user_id) do
      nil -> 
        {:error, "User not found"}
      
      user ->
        IO.inspect(user, label: "Found user")
        
        # Convert atom keys to string keys for database storage
        string_tokens = %{
          "access_token" => tokens[:access_token] || tokens["access_token"],
          "refresh_token" => tokens[:refresh_token] || tokens["refresh_token"],
          "token_type" => tokens[:token_type] || tokens["token_type"],
          "expires_in" => tokens[:expires_in] || tokens["expires_in"]
        }
        
        IO.inspect(string_tokens, label: "Converted tokens for storage")

        result = user
        |> User.changeset(%{hubspot_tokens: string_tokens})
        |> IO.inspect(label: "Changeset for user update")
        |> Repo.update()
        |> IO.inspect(label: "Repo update result")
        
        # Verify the update by re-fetching from database
        case result do
          {:ok, updated_user} ->
            fresh_user = Repo.get!(User, updated_user.id)
            IO.inspect(fresh_user.hubspot_tokens, label: "Fresh user hubspot_tokens from DB")
            result
          error -> error
        end
    end
  end

  def upsert_hubspot_tokens(email, tokens) when is_binary(email) do
    case get_user_by_email(email) do
      nil ->
        {:error, "User not found"}

      user ->
        user
        |> User.changeset(%{hubspot_tokens: tokens})
        |> Repo.update()
    end
  end
end
