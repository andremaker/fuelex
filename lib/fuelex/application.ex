defmodule Fuelex.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FuelexWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:fuelex, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Fuelex.PubSub},
      # Start a worker by calling: Fuelex.Worker.start_link(arg)
      # {Fuelex.Worker, arg},
      # Start to serve requests, typically the last entry
      FuelexWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Fuelex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FuelexWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
