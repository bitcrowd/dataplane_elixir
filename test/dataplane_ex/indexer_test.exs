defmodule DataplaneEx.IndexerTest do
  use ExUnit.Case, async: false

  alias DataplaneEx.Indexer

  setup do
    did1 = "did:plc:firesim1"
    did2 = "did:plc:firesim2"
    did3 = "did:plc:firesim3"
    did4 = "did:plc:firesim4"

    start_supervised!({Indexer, fan_out_limit: 2})

    %{
      users_csv: users_csv(did1, did2, did3, did4),
      edges_csv: edges_csv(did1, did2, did3, did4),
      did1: did1,
      did2: did2,
      did3: did3,
      did4: did4
    }
  end

  describe "bulk_users/1" do
    test "inserts all users from CSV", %{users_csv: users_csv} do
      assert :ok = Indexer.bulk_users(users_csv)
      assert Indexer.count_users() == 4
    end

    test "accepts a CSV stream", %{users_csv: users_csv} do
      assert :ok = Indexer.bulk_users(String.splitter(users_csv, "\n", trim: false))
      assert Indexer.count_users() == 4
    end
  end

  describe "bulk_follows/1" do
    test "inserts all follow edges from CSV", %{users_csv: users_csv, edges_csv: edges_csv} do
      Indexer.bulk_users(users_csv)

      assert :ok = Indexer.bulk_follows(edges_csv)
      assert Indexer.count_follows() == 4
    end

    test "accepts a CSV stream", %{users_csv: users_csv, edges_csv: edges_csv} do
      Indexer.bulk_users(users_csv)

      assert :ok = Indexer.bulk_follows(String.splitter(edges_csv, "\n", trim: false))
      assert Indexer.count_follows() == 4
    end

    test "populates followers table correctly", %{
      users_csv: users_csv,
      edges_csv: edges_csv,
      did1: did1,
      did2: did2,
      did3: did3,
      did4: did4
    } do
      Indexer.bulk_users(users_csv)
      Indexer.bulk_follows(edges_csv)

      assert Enum.sort(Indexer.followers(did1)) == [did2, did3, did4]
      assert Indexer.followers(did2) == [did3]
      assert Indexer.followers(did3) == []
      assert Indexer.followers(did4) == []
    end

    test "populates following table correctly", %{
      users_csv: users_csv,
      edges_csv: edges_csv,
      did1: did1,
      did2: did2,
      did3: did3,
      did4: did4
    } do
      Indexer.bulk_users(users_csv)
      Indexer.bulk_follows(edges_csv)

      assert Indexer.following(did1) == []
      assert Indexer.following(did2) == [did1]
      assert Enum.sort(Indexer.following(did3)) == [did1, did2]
      assert Indexer.following(did4) == [did1]
    end
  end

  describe "bulk_load_posts/2" do
    setup %{users_csv: users_csv, edges_csv: edges_csv} do
      Indexer.bulk_users(users_csv)
      Indexer.bulk_follows(edges_csv)

      %{posts_csv: posts_csv("did:plc:firesim1", "did:plc:firesim2")}
    end

    test "inserts all posts from CSV", %{posts_csv: posts_csv} do
      assert :ok = Indexer.bulk_load_posts(posts_csv)
      assert Indexer.posts_created() == 3
    end

    test "fans out posts to followers' feeds", %{posts_csv: posts_csv} do
      Indexer.bulk_load_posts(String.splitter(posts_csv, "\n", trim: false))

      timeline_2 = Indexer.get_timeline("did:plc:firesim2")
      timeline_3 = Indexer.get_timeline("did:plc:firesim3")

      assert length(timeline_2) == 2
      assert length(timeline_3) == 3
    end

    test "accepts and ignores time_offset_ms option", %{posts_csv: posts_csv} do
      assert :ok = Indexer.bulk_load_posts(posts_csv, time_offset_ms: -86_400_000)
      assert Indexer.posts_created() == 3
    end

    test "returns :ok for empty post file" do
      assert :ok = Indexer.bulk_load_posts(empty_posts_csv())
      assert Indexer.posts_created() == 0
    end
  end

  describe "toggle_follow/1" do
    test "toggles an existing relationship off and then on",
         %{users_csv: users_csv, edges_csv: edges_csv, did1: did1, did2: did2} do
      Indexer.bulk_users(users_csv)
      Indexer.bulk_follows(edges_csv)

      assert Indexer.following(did2) == [did1]
      assert :ok = Indexer.toggle_follow(%{actor_id: did2, subject_id: did1})
      assert Indexer.following(did2) == []
      assert Enum.sort(Indexer.followers(did1)) == ["did:plc:firesim3", "did:plc:firesim4"]

      assert :ok = Indexer.toggle_follow(%{actor_id: did2, subject_id: did1})
      assert Indexer.following(did2) == [did1]
      assert Enum.sort(Indexer.followers(did1)) == [did2, "did:plc:firesim3", "did:plc:firesim4"]
    end
  end

  describe "vacuum/0" do
    test "removes all data and resets post counter", %{
      users_csv: users_csv,
      edges_csv: edges_csv,
      did1: did1,
      did2: did2
    } do
      Indexer.bulk_users(users_csv)
      Indexer.bulk_follows(edges_csv)
      Indexer.insert_post(Indexer.next_post_id(), did1)
      Indexer.insert_post(Indexer.next_post_id(), did2)

      assert :ets.info(Indexer.feeds_table(), :size) > 0

      assert :ok = Indexer.vacuum()
      assert Indexer.count_users() == 0
      assert Indexer.count_follows() == 0
      assert Indexer.followers(did1) == []
      assert Indexer.following("did:plc:firesim3") == []
      assert :ets.info(Indexer.posts_table(), :size) == 0
      assert :ets.info(Indexer.feeds_table(), :size) == 0
      assert :ets.info(Indexer.celebrity_posts_table(), :size) == 0
      assert Indexer.next_post_id() == 1
    end
  end

  describe "count_users/0" do
    test "returns zero when empty" do
      assert Indexer.count_users() == 0
    end
  end

  describe "count_follows/0" do
    test "returns zero when empty" do
      assert Indexer.count_follows() == 0
    end
  end

  describe "create_post/1" do
    test "creates a post and fans out to followers", %{
      users_csv: users_csv,
      edges_csv: edges_csv,
      did1: did1,
      did2: did2,
      did3: did3,
      did4: did4
    } do
      Indexer.bulk_users(users_csv)
      Indexer.bulk_follows(edges_csv)

      assert :ok = Indexer.create_post(%{user_id: did1})

      assert length(Indexer.get_timeline(did2)) == 1
      assert length(Indexer.get_timeline(did3)) == 1
      assert length(Indexer.get_timeline(did4)) == 1
    end

    test "returns :ok for user with no followers", %{
      users_csv: users_csv,
      edges_csv: edges_csv,
      did1: did1,
      did2: did2,
      did3: did3,
      did4: did4
    } do
      Indexer.bulk_users(users_csv)
      Indexer.bulk_follows(edges_csv)

      assert :ok = Indexer.create_post(%{user_id: did4})

      assert Indexer.get_timeline(did1) == []
      assert Indexer.get_timeline(did2) == []
      assert Indexer.get_timeline(did3) == []
    end
  end

  describe "next_post_id/0" do
    test "returns sequential IDs starting from 1" do
      assert Indexer.next_post_id() == 1
      assert Indexer.next_post_id() == 2
      assert Indexer.next_post_id() == 3
    end
  end

  describe "insert_post/2" do
    test "inserts a post with author into the posts table" do
      id = Indexer.next_post_id()
      Indexer.insert_post(id, 42)

      assert [{^id, 42}] = :ets.lookup(Indexer.posts_table(), id)
      assert :ets.info(Indexer.posts_table(), :size) == 1
    end

    test "multiple posts are stored independently" do
      for author <- [1, 1, 2, 3, 3] do
        Indexer.insert_post(Indexer.next_post_id(), author)
      end

      assert :ets.info(Indexer.posts_table(), :size) == 5
    end

    test "fans out to followers' feeds", %{
      users_csv: users_csv,
      edges_csv: edges_csv,
      did1: did1,
      did2: did2,
      did3: did3,
      did4: did4
    } do
      Indexer.bulk_users(users_csv)
      Indexer.bulk_follows(edges_csv)

      p1 = Indexer.next_post_id()
      Indexer.insert_post(p1, did1)

      assert Enum.sort(Indexer.get_timeline(did2)) == [p1]
      assert Enum.sort(Indexer.get_timeline(did3)) == [p1]
      assert Enum.sort(Indexer.get_timeline(did4)) == [p1]
      assert Indexer.get_timeline(did1) == []
    end

    test "fans out to correct followers for different authors", %{
      users_csv: users_csv,
      edges_csv: edges_csv,
      did1: did1,
      did2: did2,
      did3: did3,
      did4: did4
    } do
      Indexer.bulk_users(users_csv)
      Indexer.bulk_follows(edges_csv)

      p1 = Indexer.next_post_id()
      p2 = Indexer.next_post_id()
      Indexer.insert_post(p1, did1)
      Indexer.insert_post(p2, did2)

      assert Enum.sort(Indexer.get_timeline(did3)) == Enum.sort([p1, p2])
      assert Indexer.get_timeline(did4) == [p1]
      assert Indexer.get_timeline(did2) == [p1]
    end

    test "no fan-out when author has no followers" do
      Indexer.insert_post(Indexer.next_post_id(), 999)

      assert :ets.info(Indexer.feeds_table(), :size) == 0
    end

    test "skips fan-out and stores in celebrity_posts when follower count exceeds fan_out_limit",
         %{
           users_csv: users_csv,
           edges_csv: edges_csv,
           did1: did1
         } do
      Indexer.bulk_users(users_csv)
      Indexer.bulk_follows(edges_csv)

      post_id = Indexer.next_post_id()
      Indexer.insert_post(post_id, did1)

      assert :ets.info(Indexer.feeds_table(), :size) == 0
      assert :ets.info(Indexer.posts_table(), :size) == 1
      assert [{^did1, ^post_id}] = :ets.lookup(Indexer.celebrity_posts_table(), did1)
    end

    test "allows fan-out when follower count is within fan_out_limit", %{
      users_csv: users_csv,
      edges_csv: edges_csv,
      did2: did2,
      did3: did3
    } do
      Indexer.bulk_users(users_csv)
      Indexer.bulk_follows(edges_csv)

      # User 2 has 1 follower — within limit, fan-out happens
      post_id = Indexer.next_post_id()
      Indexer.insert_post(post_id, did2)
      assert Indexer.get_timeline(did3) == [post_id]
    end

    test "fan-out works normally when fan_out_limit is not configured", %{
      users_csv: users_csv,
      edges_csv: edges_csv,
      did1: did1,
      did2: did2,
      did3: did3,
      did4: did4
    } do
      :persistent_term.put(:indexer_ets_config, %{})

      Indexer.bulk_users(users_csv)
      Indexer.bulk_follows(edges_csv)

      Indexer.insert_post(Indexer.next_post_id(), did1)
      assert length(Indexer.get_timeline(did2)) == 1
      assert length(Indexer.get_timeline(did3)) == 1
      assert length(Indexer.get_timeline(did4)) == 1
    end
  end

  describe "insert_feed_entry/2 and get_timeline/1" do
    test "get_timeline returns post IDs added to a user's feed" do
      Indexer.insert_feed_entry(1, 100)
      Indexer.insert_feed_entry(1, 200)
      Indexer.insert_feed_entry(1, 300)

      assert Enum.sort(Indexer.get_timeline(1)) == [100, 200, 300]
    end

    test "feeds are isolated per user" do
      Indexer.insert_feed_entry(1, 100)
      Indexer.insert_feed_entry(2, 200)
      Indexer.insert_feed_entry(1, 300)

      assert Enum.sort(Indexer.get_timeline(1)) == [100, 300]
      assert Indexer.get_timeline(2) == [200]
    end

    test "get_timeline returns empty list for user with no feed entries" do
      assert Indexer.get_timeline(999) == []
    end
  end

  describe "get_timeline/1 with celebrity posts" do
    setup %{users_csv: users_csv, edges_csv: edges_csv} do
      Indexer.bulk_users(users_csv)
      Indexer.bulk_follows(edges_csv)
      :ok
    end

    test "includes celebrity posts from followed authors", %{
      did1: did1,
      did2: did2,
      did3: did3,
      did4: did4
    } do
      post_id = Indexer.next_post_id()
      Indexer.insert_post(post_id, did1)

      assert Indexer.get_timeline(did2) == [post_id]
      assert Indexer.get_timeline(did3) == [post_id]
      assert Indexer.get_timeline(did4) == [post_id]
    end

    test "excludes celebrity posts from non-followed authors", %{did1: did1} do
      Indexer.insert_post(Indexer.next_post_id(), did1)

      assert Indexer.get_timeline(did1) == []
    end

    test "merges fan-out and celebrity posts", %{did1: did1, did2: did2, did3: did3} do
      celebrity_post = Indexer.next_post_id()
      Indexer.insert_post(celebrity_post, did1)

      normal_post = Indexer.next_post_id()
      Indexer.insert_post(normal_post, did2)

      assert Enum.sort(Indexer.get_timeline(did3)) == Enum.sort([celebrity_post, normal_post])
    end
  end

  describe "user_exists?/1" do
    test "returns true for loaded users", %{users_csv: users_csv, did1: did1, did4: did4} do
      Indexer.bulk_users(users_csv)

      assert Indexer.user_exists?(did1)
      assert Indexer.user_exists?(did4)
    end

    test "returns false for unknown users" do
      refute Indexer.user_exists?("did:plc:unknown")
    end
  end

  describe "posts_planned/0" do
    test "returns 0 initially" do
      assert Indexer.posts_planned() == 0
    end

    test "increments on each create_post call", %{users_csv: users_csv, edges_csv: edges_csv} do
      Indexer.bulk_users(users_csv)
      Indexer.bulk_follows(edges_csv)

      Indexer.create_post(%{user_id: 1})
      assert Indexer.posts_planned() == 1

      Indexer.create_post(%{user_id: 2})
      assert Indexer.posts_planned() == 2
    end

    test "increments even for celebrity posts", %{users_csv: users_csv, edges_csv: edges_csv} do
      Indexer.bulk_users(users_csv)
      Indexer.bulk_follows(edges_csv)

      Indexer.create_post(%{user_id: 1})
      assert Indexer.posts_planned() == 1
    end

    test "resets to 0 after vacuum" do
      Indexer.create_post(%{user_id: 1})
      assert Indexer.posts_planned() > 0

      Indexer.vacuum()
      assert Indexer.posts_planned() == 0
    end
  end

  describe "posts_created/0" do
    test "returns 0 initially" do
      assert Indexer.posts_created() == 0
    end

    test "returns the number of posts in the posts table" do
      Indexer.create_post(%{user_id: 1})
      Indexer.create_post(%{user_id: 2})

      assert Indexer.posts_created() == 2
    end

    test "matches posts_planned when all posts succeed" do
      Indexer.create_post(%{user_id: 1})
      Indexer.create_post(%{user_id: 2})
      Indexer.create_post(%{user_id: 3})

      assert Indexer.posts_planned() == Indexer.posts_created()
    end

    test "resets to 0 after vacuum" do
      Indexer.create_post(%{user_id: 1})
      assert Indexer.posts_created() > 0

      Indexer.vacuum()
      assert Indexer.posts_created() == 0
    end
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

  defp edges_csv(did1, did2, did3, did4) do
    """
    uri,cid,actor_did,subject_did
    at://something,bayfreixx,#{did2},#{did1}
    at://something,bayfreixx,#{did3},#{did1}
    at://something,bayfreixx,#{did4},#{did1}
    at://something,bayfreixx,#{did3},#{did2}
    """
  end

  defp posts_csv(did1, did2) do
    """
    offset_ms,user_id
    0,#{did1}
    1000,#{did2}
    5000,#{did1}
    """
  end

  defp empty_posts_csv do
    "offset_ms,user_id\n"
  end
end
