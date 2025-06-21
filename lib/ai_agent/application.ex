defmodule AiAgent.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AiAgentWeb.Telemetry,
      AiAgent.Repo,
      {DNSCluster, query: Application.get_env(:ai_agent, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AiAgent.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: AiAgent.Finch},
      # Start a worker by calling: AiAgent.Worker.start_link(arg)
      # {AiAgent.Worker, arg},
      # Start to serve requests, typically the last entry
      AiAgentWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AiAgent.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AiAgentWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
