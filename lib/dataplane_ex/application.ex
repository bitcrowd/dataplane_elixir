defmodule DataplaneEx.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        DataplaneExWeb.Telemetry,
        DataplaneEx.Repo,
        DataplaneEx.WriteRepo,
        dataplane_indexer(),
        {DNSCluster, query: Application.get_env(:dataplane_ex, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: DataplaneEx.PubSub},
        DataplaneExWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    children =
      if url = relay_url() do
        children ++
          [
            {DataplaneEx.SyncClient,
             uri: "#{url}/xrpc/com.atproto.sync.subscribeRepos",
             name: {:local, :simulator}}
          ]
      else
        children
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DataplaneEx.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DataplaneExWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  def relay_url() do
    Application.get_env(:dataplane_ex, :bsky_relay_websocket, nil)
  end

  def dataplane_indexer() do
    Application.get_env(:dataplane_ex, :indexer, DataplaneEx.Indexer.ETS)
  end
end
