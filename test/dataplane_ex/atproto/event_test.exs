defmodule DataplaneEx.ATProto.EventTest do
  use ExUnit.Case, async: true
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
end
