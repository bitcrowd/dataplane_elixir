defmodule DataplaneExWeb.TimelineControllerTest do
  use DataplaneExWeb.ConnCase, async: false

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
    assert length(items) == 2
    assert Enum.map(items, & &1["id"]) == Enum.sort(Enum.map(items, & &1["id"]), :desc)
  end

  defp users_csv(did1, did2, did3, did4) do
    """
    user_did,indexedAt,trustedVerifier
    #{did1},20260303,false
    #{did2},20260303,false
    #{did3},20260303,false
    #{did4},20260303,false
    """
  end

  defp follows_csv(did1, did2, did3, did4) do
    """
    uri,cid,actor_did,subject_did
    at://something,bayfreixx,#{did2},#{did1}
    at://something,bayfreixx,#{did3},#{did1}
    at://something,bayfreixx,#{did4},#{did1}
    at://something,bayfreixx,#{did3},#{did2}
    """
  end
end
