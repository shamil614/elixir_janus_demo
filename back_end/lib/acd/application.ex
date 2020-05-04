defmodule Acd.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      Acd.Janus.HandlerSupervisor,
      Acd.Janus.SessionSupervisor,
      Acd.Janus.WebsocketSupervisor,
      {Registry, keys: :unique, name: Acd.Janus.HandlerRegistry},
      {Registry, keys: :unique, name: Acd.Janus.SessionRegistry},
      {Registry, keys: :unique, name: Acd.Janus.WebsocketRegistry},
      # Start the Ecto repository
      Acd.Repo,
      # Start the endpoint when the application starts
      AcdWeb.Endpoint,
      # Phoenix Presence module
      AcdWeb.Presence,
      # keep a global list of IceServers cached
      {Acd.Janus.IceServerCache, []}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Acd.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    AcdWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
