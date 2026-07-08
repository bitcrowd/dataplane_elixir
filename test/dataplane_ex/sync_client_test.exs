defmodule DataplaneEx.SyncClientTest do
  use ExUnit.Case, async: false
  alias DataplaneEx.SyncClient

  @moduletag :capture_log

  setup do
    Phoenix.PubSub.subscribe(DataplaneEx.PubSub, "firehose")
    :ok
  end

  describe "handle_frame/2" do
    test "broadcasts binary frames to the firehose topic" do
      assert {:ok, %{}} = SyncClient.handle_frame({:binary, "payload"}, %{})
      assert_received {:binary, "payload"}
    end

    test "ignores non-binary frames" do
      assert {:ok, %{}} = SyncClient.handle_frame({:text, "ignored"}, %{})
      refute_received {:text, "ignored"}
    end
  end

  describe "handle_connect/2" do
    test "returns the unchanged state" do
      state = %{uri: "wss://example.test"}
      assert {:ok, ^state} = SyncClient.handle_connect(%{}, state)
    end
  end

  describe "handle_disconnect/2" do
    test "reconnects after a disconnect" do
      state = %{uri: "wss://example.test"}

      assert {:reconnect, ^state} =
               SyncClient.handle_disconnect(%{reason: {:remote, :normal}}, state)

      assert {:reconnect, ^state} =
               SyncClient.handle_disconnect(%{reason: :closed, attempt_number: 3}, state)
    end
  end

  describe "handle_info/2" do
    test "returns the unchanged state for unexpected messages" do
      assert {:ok, %{}} = SyncClient.handle_info(:unexpected, %{})
    end
  end

  describe "terminate/2" do
    test "returns :ok" do
      assert SyncClient.terminate(:normal, %{}) == :ok
    end
  end

  describe "start_link/1" do
    test "starts the process" do
      assert {:ok, pid} = SyncClient.start_link(uri: "ws://127.0.0.1:1", name: :sync_client_test)
      assert Process.alive?(pid)

      Process.unlink(pid)
      Process.exit(pid, :kill)
    end
  end
end
