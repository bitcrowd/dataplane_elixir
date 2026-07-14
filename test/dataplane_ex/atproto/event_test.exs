defmodule DataplaneEx.ATProto.EventTest do
  use ExUnit.Case, async: true
  import DataplaneEx.CommitFixtures
  alias DataplaneEx.ATProto.Event

  @moduletag :capture_log

  defp frame(header, payload) do
    CBOR.encode(header) <> CBOR.encode(payload)
  end

  test "decodes identity events" do
    binary =
      frame(%{"op" => 1, "t" => "#identity"}, %{
        "seq" => 1,
        "did" => "did:plc:alice",
        "time" => "2026-01-01T00:00:00.000Z",
        "handle" => "alice.test"
      })

    assert %{kind: :identity, did: "did:plc:alice"} = Event.decode(binary)
  end

  test "ignores unknown event kinds" do
    binary = frame(%{"op" => 1, "t" => "#sync"}, %{"seq" => 1})

    assert Event.decode(binary) == []
  end

  test "ignores frames that fail to decode" do
    assert Event.decode(<<0xFF, 0xFF, 0xFF>>) == []
  end

  test "ignores events with invalid payloads" do
    binary = frame(%{"op" => 1, "t" => "#identity"}, %{"seq" => "not a number"})

    assert Event.decode(binary) == []
  end

  test "returns no events for error frames" do
    binary =
      frame(%{"op" => -1}, %{"error" => "FutureCursor", "message" => "cursor in the future"})

    assert Event.decode(binary) == []
  end

  test "decodes commit events" do
    binary =
      commit_frame("did:plc:alice", "app.bsky.feed.post", %{"$type" => "app.bsky.feed.post"})

    assert [
             %{
               kind: :commit,
               did: "did:plc:alice",
               commit: %{operation: "create", collection: "app.bsky.feed.post", rkey: "abc123"}
             }
           ] = Event.decode(binary)
  end

  test "decodes delete commit events" do
    binary = commit_frame("did:plc:alice", "app.bsky.feed.post", %{}, action: "delete")

    assert [
             %{
               kind: :commit,
               did: "did:plc:alice",
               commit: %{operation: "delete", collection: "app.bsky.feed.post", rkey: "abc123"}
             }
           ] = Event.decode(binary)
  end

  test "decodes account events" do
    binary =
      frame(%{"op" => 1, "t" => "#account"}, %{
        "seq" => 1,
        "did" => "did:plc:alice",
        "time" => "2026-01-01T00:00:00.000Z",
        "active" => true
      })

    assert %{kind: :account, did: "did:plc:alice"} = Event.decode(binary)
  end

  test "ignores invalid commit events" do
    binary = frame(%{"op" => 1, "t" => "#commit"}, %{"seq" => 1})

    assert Event.decode(binary) == []
  end

  test "ignores invalid account events" do
    binary = frame(%{"op" => 1, "t" => "#account"}, %{"seq" => "not a number"})

    assert Event.decode(binary) == []
  end
end
