#!/usr/bin/env elixir

# Debug script to check HubSpot token status in database
Mix.install([
  {:ecto_sql, "~> 3.10"},
  {:postgrex, "~> 0.17"}
])

Application.load(:ai_agent)
AiAgent.Repo.start_link()

alias AiAgent.{Repo, User}

# Find all users and check their HubSpot tokens
users = Repo.all(User)

IO.puts("\n=== HUBSPOT TOKEN DEBUG ===\n")

Enum.each(users, fn user ->
  IO.puts("User ID: #{user.id}")
  IO.puts("Email: #{user.email}")
  IO.puts("Google tokens: #{if user.google_tokens, do: "✓ Present", else: "✗ Missing"}")
  IO.puts("HubSpot tokens: #{if user.hubspot_tokens, do: "✓ Present", else: "✗ Missing"}")
  
  if user.hubspot_tokens do
    access_token = user.hubspot_tokens["access_token"]
    IO.puts("HubSpot access_token: #{if access_token, do: "✓ Present (#{String.slice(access_token, 0, 20)}...)", else: "✗ Missing"}")
    IO.puts("Full HubSpot tokens: #{inspect(user.hubspot_tokens)}")
  end
  
  IO.puts("Created: #{user.inserted_at}")
  IO.puts("Updated: #{user.updated_at}")
  IO.puts("---")
end)

if Enum.empty?(users) do
  IO.puts("No users found in database!")
end

IO.puts("\n=== END DEBUG ===\n")