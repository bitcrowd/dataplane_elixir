defmodule DataplaneEx.SyncClient do
  use Fresh

  alias Phoenix.PubSub

  require Logger

  def start_link(opts) do
    uri = opts[:uri]
    name = opts[:name]
    state = %{uri: uri}

    Fresh.start_link(uri, __MODULE__, state, name: name)
  end

  def handle_connect(_status, _headers, state) do
    Logger.debug("[SyncClient] connected to #{state.uri}")
    {:ok, state}
  end

  def handle_control(_data, state) do
    {:ok, state}
  end

  def handle_disconnect(_code, _reason, state) do
    Logger.debug("[SyncClient] disconnected")
    Logger.debug("[SyncClient] reconnecting...")
    {:reconnect, state}
  end

  def handle_error(error, state) do
    Logger.error("[SyncClient] error: #{inspect(error)}")
    Logger.debug("[SyncClient] reconnecting...")
    {:reconnect, state}
  end

  def handle_in(event, state) do
    PubSub.broadcast(DataplaneEx.PubSub, "firehose", event)
    {:ok, state}
  end

  def handle_info(_data, state) do
    Logger.debug("[SyncClient] unknown data")
    {:ok, state}
  end

  def handle_terminate(_reason, state) do
    Logger.debug("[SyncClient] terminating")
    {:terminating, state}
  end
end
