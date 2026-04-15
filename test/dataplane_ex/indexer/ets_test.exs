defmodule DataplaneEx.Indexer.ETSTest do
  use ExUnit.Case, async: false

  alias DataplaneEx.Indexer.ETS, as: Indexer

  setup do
    users_path = tmp_path("users")
    edges_path = tmp_path("edges")

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
    Indexer.configure([])

    on_exit(fn ->
      File.rm(users_path)
      File.rm(edges_path)
    end)

    %{users_path: users_path, edges_path: edges_path}
  end

  describe "configure/1" do
    test "accepts empty options" do
      assert :ok = Indexer.configure([])
    end

    test "accepts fan_out_limit option" do
      assert :ok = Indexer.configure(fan_out_limit: 100)
    end

    test "raises on unsupported options" do
      assert_raise ArgumentError, ~r/unsupported indexer options/, fn ->
        Indexer.configure(batch_size: 100)
      end
    end
  end

  describe "bulk_users/1" do
    test "inserts all users from CSV", %{users_path: path} do
      assert :ok = Indexer.bulk_users(path)
      assert Indexer.count_users() == 4
    end
  end

  describe "bulk_follows/1" do
    test "inserts all follow edges from CSV", %{users_path: users_path, edges_path: edges_path} do
      Indexer.bulk_users(users_path)

      assert :ok = Indexer.bulk_follows(edges_path)
      assert Indexer.count_follows() == 4
    end

    test "populates followers table correctly", %{users_path: users_path, edges_path: edges_path} do
      Indexer.bulk_users(users_path)
      Indexer.bulk_follows(edges_path)

      assert Enum.sort(Indexer.followers(1)) == [2, 3, 4]
      assert Indexer.followers(2) == [3]
      assert Indexer.followers(3) == []
      assert Indexer.followers(4) == []
    end

    test "populates following table correctly", %{users_path: users_path, edges_path: edges_path} do
      Indexer.bulk_users(users_path)
      Indexer.bulk_follows(edges_path)

      assert Indexer.following(1) == []
      assert Indexer.following(2) == [1]
      assert Enum.sort(Indexer.following(3)) == [1, 2]
      assert Indexer.following(4) == [1]
    end
  end

  describe "bulk_load_posts/2" do
    setup %{users_path: users_path, edges_path: edges_path} do
      Indexer.bulk_users(users_path)
      Indexer.bulk_follows(edges_path)

      posts_path = tmp_path("posts")

      File.write!(posts_path, """
      offset_ms,user_id
      0,1
      1000,2
      5000,1
      """)

      on_exit(fn -> File.rm(posts_path) end)

      %{posts_path: posts_path}
    end

    test "inserts all posts from CSV", %{posts_path: posts_path} do
      assert :ok = Indexer.bulk_load_posts(posts_path)
      assert Indexer.posts_created() == 3
    end

    test "fans out posts to followers' feeds", %{posts_path: posts_path} do
      Indexer.bulk_load_posts(posts_path)

      timeline_2 = Indexer.get_timeline(2)
      timeline_3 = Indexer.get_timeline(3)

      assert length(timeline_2) == 2
      assert length(timeline_3) == 3
    end

    test "accepts and ignores time_offset_ms option", %{posts_path: posts_path} do
      assert :ok = Indexer.bulk_load_posts(posts_path, time_offset_ms: -86_400_000)
      assert Indexer.posts_created() == 3
    end

    test "returns :ok for empty post file" do
      empty_path = tmp_path("empty_posts")
      File.write!(empty_path, "offset_ms,user_id\n")
      on_exit(fn -> File.rm(empty_path) end)

      assert :ok = Indexer.bulk_load_posts(empty_path)
      assert Indexer.posts_created() == 0
    end
  end

  describe "toggle_follow/1" do
    test "toggles an existing relationship off and then on",
         %{users_path: users_path, edges_path: edges_path} do
      Indexer.bulk_users(users_path)
      Indexer.bulk_follows(edges_path)

      assert Indexer.following(2) == [1]
      assert :ok = Indexer.toggle_follow(%{actor_id: 2, subject_id: 1})
      assert Indexer.following(2) == []
      assert Enum.sort(Indexer.followers(1)) == [3, 4]

      assert :ok = Indexer.toggle_follow(%{actor_id: 2, subject_id: 1})
      assert Indexer.following(2) == [1]
      assert Enum.sort(Indexer.followers(1)) == [2, 3, 4]
    end
  end

  describe "vacuum/0" do
    test "removes all data and resets post counter", %{
      users_path: users_path,
      edges_path: edges_path
    } do
      Indexer.bulk_users(users_path)
      Indexer.bulk_follows(edges_path)
      Indexer.insert_post(Indexer.next_post_id(), 1)
      Indexer.insert_post(Indexer.next_post_id(), 2)

      assert :ets.info(Indexer.feeds_table(), :size) > 0

      assert :ok = Indexer.vacuum()
      assert Indexer.count_users() == 0
      assert Indexer.count_follows() == 0
      assert Indexer.followers(1) == []
      assert Indexer.following(3) == []
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
      users_path: users_path,
      edges_path: edges_path
    } do
      Indexer.bulk_users(users_path)
      Indexer.bulk_follows(edges_path)

      assert :ok = Indexer.create_post(%{user_id: 1})

      assert length(Indexer.get_timeline(2)) == 1
      assert length(Indexer.get_timeline(3)) == 1
      assert length(Indexer.get_timeline(4)) == 1
    end

    test "returns :ok for user with no followers", %{
      users_path: users_path,
      edges_path: edges_path
    } do
      Indexer.bulk_users(users_path)
      Indexer.bulk_follows(edges_path)

      assert :ok = Indexer.create_post(%{user_id: 4})

      assert Indexer.get_timeline(1) == []
      assert Indexer.get_timeline(2) == []
      assert Indexer.get_timeline(3) == []
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

    test "fans out to followers' feeds", %{users_path: users_path, edges_path: edges_path} do
      Indexer.bulk_users(users_path)
      Indexer.bulk_follows(edges_path)

      p1 = Indexer.next_post_id()
      Indexer.insert_post(p1, 1)

      assert Enum.sort(Indexer.get_timeline(2)) == [p1]
      assert Enum.sort(Indexer.get_timeline(3)) == [p1]
      assert Enum.sort(Indexer.get_timeline(4)) == [p1]
      assert Indexer.get_timeline(1) == []
    end

    test "fans out to correct followers for different authors", %{
      users_path: users_path,
      edges_path: edges_path
    } do
      Indexer.bulk_users(users_path)
      Indexer.bulk_follows(edges_path)

      p1 = Indexer.next_post_id()
      p2 = Indexer.next_post_id()
      Indexer.insert_post(p1, 1)
      Indexer.insert_post(p2, 2)

      assert Enum.sort(Indexer.get_timeline(3)) == Enum.sort([p1, p2])
      assert Indexer.get_timeline(4) == [p1]
      assert Indexer.get_timeline(2) == [p1]
    end

    test "no fan-out when author has no followers" do
      Indexer.insert_post(Indexer.next_post_id(), 999)

      assert :ets.info(Indexer.feeds_table(), :size) == 0
    end

    test "skips fan-out and stores in celebrity_posts when follower count exceeds fan_out_limit",
         %{
           users_path: users_path,
           edges_path: edges_path
         } do
      Indexer.configure(fan_out_limit: 2)
      Indexer.bulk_users(users_path)
      Indexer.bulk_follows(edges_path)

      post_id = Indexer.next_post_id()
      Indexer.insert_post(post_id, 1)

      assert :ets.info(Indexer.feeds_table(), :size) == 0
      assert :ets.info(Indexer.posts_table(), :size) == 1
      assert [{1, ^post_id}] = :ets.lookup(Indexer.celebrity_posts_table(), 1)
    end

    test "allows fan-out when follower count is within fan_out_limit", %{
      users_path: users_path,
      edges_path: edges_path
    } do
      Indexer.configure(fan_out_limit: 2)
      Indexer.bulk_users(users_path)
      Indexer.bulk_follows(edges_path)

      # User 2 has 1 follower — within limit, fan-out happens
      post_id = Indexer.next_post_id()
      Indexer.insert_post(post_id, 2)
      assert Indexer.get_timeline(3) == [post_id]
    end

    test "fan-out works normally when fan_out_limit is not configured", %{
      users_path: users_path,
      edges_path: edges_path
    } do
      Indexer.configure([])
      Indexer.bulk_users(users_path)
      Indexer.bulk_follows(edges_path)

      Indexer.insert_post(Indexer.next_post_id(), 1)
      assert length(Indexer.get_timeline(2)) == 1
      assert length(Indexer.get_timeline(3)) == 1
      assert length(Indexer.get_timeline(4)) == 1
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
    setup %{users_path: users_path, edges_path: edges_path} do
      Indexer.configure(fan_out_limit: 2)
      Indexer.bulk_users(users_path)
      Indexer.bulk_follows(edges_path)
      :ok
    end

    test "includes celebrity posts from followed authors" do
      post_id = Indexer.next_post_id()
      Indexer.insert_post(post_id, 1)

      assert Indexer.get_timeline(2) == [post_id]
      assert Indexer.get_timeline(3) == [post_id]
      assert Indexer.get_timeline(4) == [post_id]
    end

    test "excludes celebrity posts from non-followed authors" do
      Indexer.insert_post(Indexer.next_post_id(), 1)

      assert Indexer.get_timeline(1) == []
    end

    test "merges fan-out and celebrity posts" do
      celebrity_post = Indexer.next_post_id()
      Indexer.insert_post(celebrity_post, 1)

      normal_post = Indexer.next_post_id()
      Indexer.insert_post(normal_post, 2)

      assert Enum.sort(Indexer.get_timeline(3)) == Enum.sort([celebrity_post, normal_post])
    end
  end

  describe "user_exists?/1" do
    test "returns true for loaded users", %{users_path: path} do
      Indexer.bulk_users(path)

      assert Indexer.user_exists?(1)
      assert Indexer.user_exists?(4)
    end

    test "returns false for unknown users" do
      refute Indexer.user_exists?(999)
    end
  end

  describe "posts_planned/0" do
    test "returns 0 initially" do
      assert Indexer.posts_planned() == 0
    end

    test "increments on each create_post call", %{users_path: users_path, edges_path: edges_path} do
      Indexer.bulk_users(users_path)
      Indexer.bulk_follows(edges_path)

      Indexer.create_post(%{user_id: 1})
      assert Indexer.posts_planned() == 1

      Indexer.create_post(%{user_id: 2})
      assert Indexer.posts_planned() == 2
    end

    test "increments even for celebrity posts", %{users_path: users_path, edges_path: edges_path} do
      Indexer.configure(fan_out_limit: 2)
      Indexer.bulk_users(users_path)
      Indexer.bulk_follows(edges_path)

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

  defp tmp_path(name) do
    Path.join(System.tmp_dir!(), "dataplane_ex_#{name}_#{System.unique_integer([:positive])}.csv")
  end
end
