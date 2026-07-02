defmodule DataplaneExWeb.TimelineControllerTest do
  use DataplaneExWeb.ConnCase, async: false
  import DataplaneEx.CSVFixtures
  alias DataplaneEx.Indexer

  @moduletag :capture_log

  setup do
    start_supervised!(Indexer)

    did1 = "did:plc:firesim1"
    did2 = "did:plc:firesim2"
    did3 = "did:plc:firesim3"
    did4 = "did:plc:firesim4"

    :ok = Indexer.bulk_users(users_csv(did1, did2, did3, did4))
    :ok = Indexer.bulk_follows(follows_csv(did1, did2, did3, did4))

    :ok
  end

  test "returns timeline items for the supplied actor_did", %{conn: conn} do
    Indexer.create_post(%{user_id: "did:plc:firesim2"})
    Indexer.create_post(%{user_id: "did:plc:firesim3"})
    Indexer.create_post(%{user_id: "did:plc:firesim2"})

    conn = post(conn, ~p"/bsky.Service/GetTimeline", actor_did: "did:plc:firesim3", limit: 2)

    assert %{"items" => items} = json_response(conn, 200)
    assert [_, _] = items
    assert Enum.map(items, & &1["id"]) == Enum.sort(Enum.map(items, & &1["id"]), :desc)
  end
end
