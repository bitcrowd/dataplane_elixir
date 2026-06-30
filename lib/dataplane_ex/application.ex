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
        {DNSCluster, query: Application.get_env(:dataplane_ex, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: DataplaneEx.PubSub},
        dataplane_indexer(),
        DataplaneExWeb.Endpoint,
        sync_client()
      ]
      |> Enum.reject(&is_nil/1)

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

  def dataplane_indexer() do
    Application.get_env(:dataplane_ex, :indexer, DataplaneEx.Indexer.ETS)
  end

  def sync_client() do
    if url = relay_url() do
      {DataplaneEx.SyncClient,
       uri: "#{url}/xrpc/com.atproto.sync.subscribeRepos", name: :sync}
    end
  end

  def relay_url() do
    Application.get_env(:dataplane_ex, :bsky_relay_websocket, nil)
  end
end
