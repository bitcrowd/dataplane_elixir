defmodule DataplaneEx.SyncClient do
  @moduledoc """
  WebSocket client that streams firehose sync events into Phoenix PubSub.
  """

  use WebSockex

  alias Phoenix.PubSub

  require Logger

  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts) do
    uri = Keyword.fetch!(opts, :uri)
    name = Keyword.fetch!(opts, :name)

    WebSockex.start_link(uri, __MODULE__, %{uri: uri},
      name: name,
      async: true,
      handle_initial_conn_failure: true
    )
  end

  @impl WebSockex
  def handle_connect(_conn, state) do
    Logger.debug("[SyncClient] connected to #{state.uri}")
    {:ok, state}
  end

  @impl WebSockex
  def handle_frame({:binary, _data} = frame, state) do
    PubSub.broadcast(DataplaneEx.PubSub, "firehose", frame)
    {:ok, state}
  end

  def handle_frame(_frame, state), do: {:ok, state}

  @impl WebSockex
  def handle_disconnect(%{reason: {_source, :normal}}, state) do
    Logger.debug("[SyncClient] disconnected, reconnecting...")
    {:reconnect, state}
  end

  def handle_disconnect(%{reason: reason, attempt_number: attempt}, state) do
    Logger.error(
      "[SyncClient] disconnected: #{inspect(reason)} (attempt #{attempt}), reconnecting..."
    )

    {:reconnect, state}
  end

  @impl WebSockex
  def handle_info(message, state) do
    Logger.debug("[SyncClient] unexpected message: #{inspect(message)}")
    {:ok, state}
  end

  @impl WebSockex
  def terminate(reason, _state) do
    Logger.debug("[SyncClient] terminating: #{inspect(reason)}")
    :ok
  end
end
