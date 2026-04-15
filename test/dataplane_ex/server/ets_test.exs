defmodule DataplaneEx.Server.ETSTest do
  use ExUnit.Case, async: false

  alias DataplaneEx.Server.ETS, as: Server
  alias DataplaneEx.Indexer.ETS, as: Indexer

  @fixtures_dir Path.expand("../../../fixtures", __DIR__)

  setup do
    users_path = Path.join(@fixtures_dir, "server_users.csv")
    edges_path = Path.join(@fixtures_dir, "server_edges.csv")

    File.mkdir_p!(@fixtures_dir)

    File.write!(users_path, """
    user_id,follower_count,followers...
    1,3,2,3,4
    2,1,3
    3,0
    4,0
    """)

    File.write!(edges_path, """
    actor_id,subject_id
    2,1
    3,1
    4,1
    3,2
    """)

    start_supervised!(Indexer)

    Indexer.bulk_users(users_path)
    Indexer.bulk_follows(edges_path)

    on_exit(fn ->
      File.rm(users_path)
      File.rm(edges_path)
    end)

    :ok
  end

  describe "get_timeline/1" do
    test "returns posts from followed users" do
      Indexer.create_post(%{user_id: 1})
      Indexer.create_post(%{user_id: 2})

      {:ok, timeline} = Server.get_timeline({3, 10, nil})
      assert length(timeline) == 2
    end

    test "respects the limit parameter" do
      for _ <- 1..5, do: Indexer.create_post(%{user_id: 1})

      {:ok, timeline} = Server.get_timeline({2, 3, nil})
      assert length(timeline) == 3
    end

    test "returns empty list for user with no follows" do
      Indexer.create_post(%{user_id: 2})

      {:ok, timeline} = Server.get_timeline({1, 10, nil})
      assert timeline == []
    end

    test "returns empty list when no posts exist" do
      {:ok, timeline} = Server.get_timeline({2, 10, nil})
      assert timeline == []
    end

    test "returns posts sorted by ID descending" do
      Indexer.create_post(%{user_id: 1})
      Indexer.create_post(%{user_id: 1})
      Indexer.create_post(%{user_id: 1})

      {:ok, timeline} = Server.get_timeline({2, 10, nil})
      ids = Enum.map(timeline, & &1.id)

      assert ids == Enum.sort(ids, :desc)
    end
  end
end
