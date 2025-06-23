defmodule AiAgent.HealthCheck do
  @moduledoc """
  Provides health check functions for the application, particularly for database connectivity.
  Used by the health check controller and can be called from other parts of the application.
  """

  alias AiAgent.Repo
  import Ecto.Query
  require Logger

  @doc """
  Checks if the database is accessible and returns a map with status information.
  """
  def check_database do
    try do
      # Simple query to check if we can connect to the database
      migration_count = Repo.aggregate(from(u in "schema_migrations", select: count()), :count)

      Logger.info("Database connectivity check passed. Found #{migration_count} migrations.")

      %{
        status: :ok,
        connected: true,
        message: "Database connection successful",
        details: %{
          migration_count: migration_count,
          timestamp: DateTime.utc_now()
        }
      }
    rescue
      e ->
        Logger.error("Database connectivity check failed: #{Exception.message(e)}")

        %{
          status: :error,
          connected: false,
          message: "Database connection failed: #{Exception.message(e)}",
          details: %{
            error_type: e.__struct__,
            timestamp: DateTime.utc_now()
          }
        }
    end
  end

  @doc """
  Checks if the database has the pgvector extension installed.
  """
  def check_pgvector do
    try do
      # Check if pgvector extension is installed
      result = Repo.query("SELECT extname FROM pg_extension WHERE extname = 'vector'")

      case result do
        {:ok, %{num_rows: 1}} ->
          Logger.info("pgvector extension is installed")
          %{status: :ok, installed: true, message: "pgvector extension is installed"}

        {:ok, %{num_rows: 0}} ->
          Logger.warn("pgvector extension is NOT installed")
          %{status: :error, installed: false, message: "pgvector extension is not installed"}

        {:error, error} ->
          Logger.error("Failed to check pgvector extension: #{inspect(error)}")
          %{status: :error, installed: false, message: "Failed to check pgvector extension", error: inspect(error)}
      end
    rescue
      e ->
        Logger.error("pgvector check failed: #{Exception.message(e)}")
        %{status: :error, installed: false, message: "Failed to check pgvector extension", error: Exception.message(e)}
    end
  end

  @doc """
  Performs a comprehensive health check of the application.
  """
  def check_system do
    db_status = check_database()
    pgvector_status = check_pgvector()

    # Overall status is ok only if all checks pass
    overall_status = if db_status.status == :ok and pgvector_status.status == :ok, do: :ok, else: :error

    %{
      status: overall_status,
      timestamp: DateTime.utc_now(),
      database: db_status,
      pgvector: pgvector_status,
      environment: %{
        hostname: get_hostname(),
        elixir_version: System.version(),
        otp_version: :erlang.system_info(:otp_release) |> List.to_string(),
        phoenix_env: Application.get_env(:ai_agent, :env, Mix.env()),
        database_url_set: System.get_env("DATABASE_URL") != nil
      }
    }
  end

  defp get_hostname do
    case :inet.gethostname() do
      {:ok, hostname} -> List.to_string(hostname)
      _ -> "unknown"
    end
  end
end
