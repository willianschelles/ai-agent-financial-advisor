defmodule AiAgent.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :ai_agent

  def migrate do
    load_app()

    # Log connection info for debugging
    database_url = System.get_env("DATABASE_URL")

    if database_url do
      # Parse URL and mask credentials
      url = URI.parse(database_url)
      masked_url = %{url | userinfo: "****:****"} |> URI.to_string()
      IO.puts("Database URL (masked): #{masked_url}")

      # Check if we can resolve the hostname
      host = url.host
      IO.puts("Checking DNS resolution for: #{host}")

      case :inet.gethostbyname(String.to_charlist(host)) do
        {:ok, _} -> IO.puts("✅ Host resolution successful")
        {:error, reason} -> IO.puts("❌ Host resolution failed: #{inspect(reason)}")
      end
    else
      IO.puts("⚠️ DATABASE_URL environment variable is not set")
    end

    # Try to connect to the database
    IO.puts("Attempting database connection...")

    try do
      for repo <- repos() do
        IO.puts("Running migrations for #{inspect(repo)}...")
        case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true)) do
          {:ok, _, _} ->
            IO.puts("✅ Migrations completed successfully for #{inspect(repo)}")
          error ->
            IO.puts("❌ Migration error for #{inspect(repo)}: #{inspect(error)}")
            raise "Migration failed for #{inspect(repo)}: #{inspect(error)}"
        end
      end
      IO.puts("✅ All migrations completed successfully")
    rescue
      e ->
        IO.puts("❌ Migration error: #{inspect(e)}")
        IO.puts("❌ Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
        raise e
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
