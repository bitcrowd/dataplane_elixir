defmodule DataplaneEx.ATProto.CommitTest do
  use ExUnit.Case, async: true
  alias DASL.CAR.DRISL
  alias DataplaneEx.ATProto.Commit
  alias DataplaneEx.Op

  test "to_event/1 reads records from DASL CAR blocks and encodes CIDs" do
    record = %{
      "$type" => "app.bsky.feed.post",
      "createdAt" => "2026-05-19T12:00:00.000Z",
      "subject" => %{"uri" => "at://did:plc:alice/app.bsky.feed.post/root"},
      "ignored" => "not included"
    }

    {:ok, {blocks, cid}} = DRISL.add_block(%DRISL{}, record)

    commit = %Commit{
      repo: "did:plc:alice",
      rev: "3lxyz",
      blocks: blocks,
      ops: [
        %Op{
          cid: cid,
          path: "app.bsky.feed.post/abc123",
          action: "create"
        }
      ]
    }

    [event] = Commit.to_event(commit)

    assert event.did == "did:plc:alice"
    assert event.kind == :commit
    assert event.commit.rev == "3lxyz"
    assert event.commit.operation == "create"
    assert event.commit.collection == "app.bsky.feed.post"
    assert event.commit.rkey == "abc123"
    assert event.commit.cid == DASL.CID.encode(cid)

    assert event.commit.record == %{
             "$type" => "app.bsky.feed.post",
             "createdAt" => "2026-05-19T12:00:00.000Z",
             "subject" => %{"uri" => "at://did:plc:alice/app.bsky.feed.post/root"}
           }
  end

  test "to_event/1 handles delete ops without reading blocks" do
    commit = %Commit{
      repo: "did:plc:alice",
      rev: "3lxyz",
      ops: [%Op{action: "delete", path: "app.bsky.feed.post/abc123"}]
    }

    [event] = Commit.to_event(commit)

    assert event.did == "did:plc:alice"
    assert event.kind == :commit
    assert event.commit.operation == "delete"
    assert event.commit.collection == "app.bsky.feed.post"
    assert event.commit.rkey == "abc123"

    refute Map.has_key?(event.commit, :cid)
  end
end
