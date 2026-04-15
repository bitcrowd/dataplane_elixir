defmodule DataplaneExWeb.TimelineControllerTest do
  use DataplaneExWeb.ConnCase, async: false

  alias DataplaneEx.Indexer.ETS

  @moduletag :capture_log

  setup do
    start_supervised!(ETS)
    Application.put_env(:dataplane_ex, :server, DataplaneEx.Server.ETS)

    users_path = tmp_path("users")
    follows_path = tmp_path("follows")

    File.write!(users_path, """
    user_id,follower_count,followers...
    1,2,2,3
    2,0
    3,0
    """)

    File.write!(follows_path, """
    actor_id,subject_id
    1,2
    1,3
    """)

    :ok = ETS.bulk_users(users_path)
    :ok = ETS.bulk_follows(follows_path)

    on_exit(fn ->
      Application.delete_env(:dataplane_ex, :server)
      File.rm(users_path)
      File.rm(follows_path)
    end)

    :ok
  end

  test "returns timeline items for the supplied actor_did", %{conn: conn} do
    ETS.create_post(%{user_id: 2})
    ETS.create_post(%{user_id: 3})
    ETS.create_post(%{user_id: 2})

    conn = get(conn, ~p"/bsky.Service/GetTimeline?actor_did=did:plc:1&limit=2&cursor=unused")

    assert %{"items" => items} = json_response(conn, 200)
    assert length(items) == 2
    assert Enum.map(items, & &1["id"]) == Enum.sort(Enum.map(items, & &1["id"]), :desc)
  end

  test "returns bad request for an invalid actor_did", %{conn: conn} do
    conn = get(conn, ~p"/bsky.Service/GetTimeline?actor_did=did:plc:not-a-user&limit=2")

    assert %{"error" => "invalid actor_did"} = json_response(conn, 400)
  end

  test "returns bad request for an invalid limit", %{conn: conn} do
    conn = get(conn, ~p"/bsky.Service/GetTimeline?actor_did=1&limit=0")

    assert %{"error" => "invalid limit"} = json_response(conn, 400)
  end

  defp tmp_path(name) do
    Path.join(
      System.tmp_dir!(),
      "dataplane_ex_timeline_#{name}_#{System.unique_integer([:positive])}.csv"
    )
  end
end
