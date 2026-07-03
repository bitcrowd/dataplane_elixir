defmodule DataplaneEx.ATProto.CommitTest do
  use ExUnit.Case, async: true
  alias DataplaneEx.ATProto.Commit
  alias DataplaneEx.Op

  test "to_event/1 reads records from DASL CAR blocks and encodes CIDs" do
    record = %{
      "$type" => "app.bsky.feed.post",
      "createdAt" => "2026-05-19T12:00:00.000Z",
      "subject" => %{"uri" => "at://did:plc:alice/app.bsky.feed.post/root"},
      "ignored" => "not included"
    }

    {:ok, {blocks, cid}} = DASL.CAR.DRISL.add_block(%DASL.CAR.DRISL{}, record)

    commit = %Commit{
      repo: "did:plc:alice",
      rev: "3lxyz",
      blocks: blocks,
      ops: [
        %Op{
          action: "create",
          cid: cid,
          path: "app.bsky.feed.post/abc123"
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
end
