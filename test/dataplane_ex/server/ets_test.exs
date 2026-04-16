defmodule DataplaneEx.Server.ETSTest do
  use ExUnit.Case, async: false

  alias DataplaneEx.Server.ETS, as: Server
  alias DataplaneEx.Indexer.ETS, as: Indexer

  @fixtures_dir Path.expand("../../../fixtures", __DIR__)

  setup do
    users_path = Path.join(@fixtures_dir, "server_users.csv")
    edges_path = Path.join(@fixtures_dir, "server_edges.csv")

    did1 = "did:plc:firesim1"
    did2 = "did:plc:firesim2"
    did3 = "did:plc:firesim3"
    did4 = "did:plc:firesim4"

    File.mkdir_p!(@fixtures_dir)

    File.write!(users_path, """
    user_did,indexedAt,trustedVerifier
    #{did1},20260303,false
    #{did2},20260303,false
    #{did3},20260303,false
    #{did4},20260303,false
    """)

    File.write!(edges_path, """
    uri,cid,actor_did,subject_did
    at://something,bayfreixx,#{did2},#{did1}
    at://something,bayfreixx,#{did3},#{did1}
    at://something,bayfreixx,#{did4},#{did1}
    at://something,bayfreixx,#{did3},#{did2}
    """)

    start_supervised!(Indexer)

    Indexer.bulk_users(users_path)
    Indexer.bulk_follows(edges_path)

    on_exit(fn ->
      File.rm(users_path)
      File.rm(edges_path)
    end)

    %{did1: did1, did2: did2, did3: did3, did4: did4}
  end

  describe "get_timeline/1" do
    test "returns posts from followed users", %{did1: did1, did2: did2, did3: did3} do
      Indexer.create_post(%{user_id: did1})
      Indexer.create_post(%{user_id: did2})

      {:ok, timeline} = Server.get_timeline({did3, 10, nil})
      assert length(timeline) == 2
    end

    test "respects the limit parameter", %{did1: did1, did2: did2} do
      for _ <- 1..5, do: Indexer.create_post(%{user_id: did1})

      {:ok, timeline} = Server.get_timeline({did2, 3, nil})
      assert length(timeline) == 3
    end

    test "returns empty list for user with no follows", %{did1: did1, did2: did2} do
      Indexer.create_post(%{user_id: did2})

      {:ok, timeline} = Server.get_timeline({did1, 10, nil})
      assert timeline == []
    end

    test "returns empty list when no posts exist", %{did2: did2} do
      {:ok, timeline} = Server.get_timeline({did2, 10, nil})
      assert timeline == []
    end

    test "returns posts sorted by ID descending", %{did1: did1, did2: did2} do
      Indexer.create_post(%{user_id: did1})
      Indexer.create_post(%{user_id: did1})
      Indexer.create_post(%{user_id: did1})

      {:ok, timeline} = Server.get_timeline({did2, 10, nil})
      ids = Enum.map(timeline, & &1.id)

      assert ids == Enum.sort(ids, :desc)
    end
  end
end
