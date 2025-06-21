defmodule AiAgent.Repo do
  use Ecto.Repo,
    otp_app: :ai_agent,
    adapter: Ecto.Adapters.Postgres

  def init(_type, config) do
    {:ok, Keyword.put(config, :extensions, [{Pgvector.Extensions.Vector, []}])}
  end
end
