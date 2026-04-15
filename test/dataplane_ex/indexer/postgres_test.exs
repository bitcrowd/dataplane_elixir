defmodule DataplaneEx.Indexer.PostgresTest do
  use DataplaneEx.DataCase

  alias DataplaneEx.Indexer.Postgres, as: Indexer

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

    Indexer.configure([])

    on_exit(fn ->
      File.rm(users_path)
      File.rm(edges_path)
    end)

    %{users_path: users_path, edges_path: edges_path}
  end

  describe "configure/1" do
    test "accepts supported options" do
      assert :ok = Indexer.configure(batch_size: 10_000)
    end

    test "raises on unsupported options" do
      assert_raise ArgumentError, ~r/unsupported indexer options/, fn ->
        Indexer.configure(foo: :bar)
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

    test "sets inserted_at based on offset_ms", %{posts_path: posts_path} do
      Indexer.bulk_load_posts(posts_path)

      timestamps =
        from(p in "posts", select: p.inserted_at, order_by: [asc: p.inserted_at])
        |> Repo.all()

      assert length(timestamps) == 3
      [t1, t2, t3] = timestamps
      assert NaiveDateTime.compare(t1, t2) == :lt
      assert NaiveDateTime.compare(t2, t3) == :lt
    end

    test "applies negative time_offset_ms to shift timestamps into the past", %{
      posts_path: posts_path
    } do
      before_load = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:millisecond)
      Indexer.bulk_load_posts(posts_path, time_offset_ms: -86_400_000)

      latest =
        from(p in "posts", select: max(p.inserted_at))
        |> Repo.one()

      assert NaiveDateTime.compare(latest, before_load) == :lt
    end

    test "returns :ok for empty post file" do
      empty_path = tmp_path("empty_posts")
      File.write!(empty_path, "offset_ms,user_id\n")
      on_exit(fn -> File.rm(empty_path) end)

      assert :ok = Indexer.bulk_load_posts(empty_path)
      assert Indexer.posts_created() == 0
    end
  end

  describe "vacuum/0" do
    test "removes all data", %{users_path: users_path, edges_path: edges_path} do
      Indexer.bulk_users(users_path)
      Indexer.bulk_follows(edges_path)

      assert :ok = Indexer.vacuum()
      assert Indexer.count_users() == 0
      assert Indexer.count_follows() == 0
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

  describe "followers/1" do
    test "returns user IDs that follow the given user", %{
      users_path: users_path,
      edges_path: edges_path
    } do
      Indexer.bulk_users(users_path)
      Indexer.bulk_follows(edges_path)

      assert Enum.sort(Indexer.followers(1)) == [2, 3, 4]
      assert Indexer.followers(2) == [3]
      assert Indexer.followers(3) == []
      assert Indexer.followers(4) == []
    end
  end

  describe "following/1" do
    test "returns user IDs that the given user follows", %{
      users_path: users_path,
      edges_path: edges_path
    } do
      Indexer.bulk_users(users_path)
      Indexer.bulk_follows(edges_path)

      assert Indexer.following(1) == []
      assert Indexer.following(2) == [1]
      assert Enum.sort(Indexer.following(3)) == [1, 2]
      assert Indexer.following(4) == [1]
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

  describe "create_post/1" do
    test "inserts a post for a valid user", %{users_path: users_path} do
      Indexer.bulk_users(users_path)

      assert :ok = Indexer.create_post(%{user_id: 2})

      posts = Repo.all(from(p in "posts", where: p.author_id == 2, select: p.id))
      assert length(posts) > 0
    end

    test "raises on foreign key violation for non-existent user" do
      assert_raise Postgrex.Error, fn ->
        Indexer.create_post(%{user_id: 999_999})
      end
    end
  end

  describe "posts_planned/0" do
    test "returns 0 initially" do
      Indexer.vacuum()
      assert Indexer.posts_planned() == 0
    end

    test "increments on each create_post call", %{users_path: users_path} do
      Indexer.vacuum()
      Indexer.bulk_users(users_path)

      Indexer.create_post(%{user_id: 1})
      assert Indexer.posts_planned() == 1

      Indexer.create_post(%{user_id: 2})
      assert Indexer.posts_planned() == 2
    end

    test "resets to 0 after vacuum", %{users_path: users_path} do
      Indexer.bulk_users(users_path)
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

    test "returns the number of posts in the database", %{users_path: users_path} do
      Indexer.bulk_users(users_path)

      Indexer.create_post(%{user_id: 1})
      Indexer.create_post(%{user_id: 2})

      assert Indexer.posts_created() == 2
    end

    test "matches posts_planned when all posts succeed", %{users_path: users_path} do
      Indexer.vacuum()
      Indexer.bulk_users(users_path)

      Indexer.create_post(%{user_id: 1})
      Indexer.create_post(%{user_id: 2})
      Indexer.create_post(%{user_id: 3})

      assert Indexer.posts_planned() == Indexer.posts_created()
    end

    test "resets to 0 after vacuum", %{users_path: users_path} do
      Indexer.bulk_users(users_path)
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
