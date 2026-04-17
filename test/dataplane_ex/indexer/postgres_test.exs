defmodule DataplaneEx.Indexer.PostgresTest do
  use DataplaneEx.DataCase

  alias DataplaneEx.Indexer.Postgres, as: Indexer

  setup do
    start_supervised!(Indexer)

    %{users_csv: users_csv(), edges_csv: edges_csv()}
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
  end

  describe "bulk_load_posts/2" do
    setup %{users_csv: users_csv, edges_csv: edges_csv} do
      Indexer.bulk_users(users_csv)
      Indexer.bulk_follows(edges_csv)

      %{posts_csv: posts_csv()}
    end

    test "inserts all posts from CSV", %{posts_csv: posts_csv} do
      assert :ok = Indexer.bulk_load_posts(posts_csv)
      assert Indexer.posts_created() == 3
    end

    test "sets inserted_at based on offset_ms", %{posts_csv: posts_csv} do
      Indexer.bulk_load_posts(String.splitter(posts_csv, "\n", trim: false))

      timestamps =
        from(p in "posts", select: p.inserted_at, order_by: [asc: p.inserted_at])
        |> Repo.all()

      assert length(timestamps) == 3
      [t1, t2, t3] = timestamps
      assert NaiveDateTime.compare(t1, t2) == :lt
      assert NaiveDateTime.compare(t2, t3) == :lt
    end

    test "applies negative time_offset_ms to shift timestamps into the past", %{
      posts_csv: posts_csv
    } do
      before_load = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:millisecond)
      Indexer.bulk_load_posts(posts_csv, time_offset_ms: -86_400_000)

      latest =
        from(p in "posts", select: max(p.inserted_at))
        |> Repo.one()

      assert NaiveDateTime.compare(latest, before_load) == :lt
    end

    test "returns :ok for empty post file" do
      assert :ok = Indexer.bulk_load_posts(empty_posts_csv())
      assert Indexer.posts_created() == 0
    end
  end

  describe "vacuum/0" do
    test "removes all data", %{users_csv: users_csv, edges_csv: edges_csv} do
      Indexer.bulk_users(users_csv)
      Indexer.bulk_follows(edges_csv)

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
      users_csv: users_csv,
      edges_csv: edges_csv
    } do
      Indexer.bulk_users(users_csv)
      Indexer.bulk_follows(edges_csv)

      assert Enum.sort(Indexer.followers("1")) == ["2", "3", "4"]
      assert Indexer.followers("2") == ["3"]
      assert Indexer.followers("3") == []
      assert Indexer.followers("4") == []
    end
  end

  describe "following/1" do
    test "returns user IDs that the given user follows", %{
      users_csv: users_csv,
      edges_csv: edges_csv
    } do
      Indexer.bulk_users(users_csv)
      Indexer.bulk_follows(edges_csv)

      assert Indexer.following("1") == []
      assert Indexer.following("2") == ["1"]
      assert Enum.sort(Indexer.following("3")) == ["1", "2"]
      assert Indexer.following("4") == ["1"]
    end
  end

  describe "toggle_follow/1" do
    test "toggles an existing relationship off and then on",
         %{users_csv: users_csv, edges_csv: edges_csv} do
      Indexer.bulk_users(users_csv)
      Indexer.bulk_follows(edges_csv)

      assert Indexer.following("2") == ["1"]
      assert :ok = Indexer.toggle_follow(%{actor_id: "2", subject_id: "1"})
      assert Indexer.following("2") == []
      assert Enum.sort(Indexer.followers("1")) == ["3", "4"]

      assert :ok = Indexer.toggle_follow(%{actor_id: "2", subject_id: "1"})
      assert Indexer.following("2") == ["1"]
      assert Enum.sort(Indexer.followers("1")) == ["2", "3", "4"]
    end
  end

  describe "create_post/1" do
    test "inserts a post for a valid user", %{users_csv: users_csv} do
      Indexer.bulk_users(users_csv)

      assert :ok = Indexer.create_post(%{user_id: "2"})

      posts = Repo.all(from(p in "posts", where: p.author_id == "2", select: p.id))
      assert length(posts) > 0
    end

    test "raises on foreign key violation for non-existent user" do
      assert_raise Postgrex.Error, fn ->
        Indexer.create_post(%{user_id: "999999"})
      end
    end
  end

  describe "posts_planned/0" do
    test "returns 0 initially" do
      Indexer.vacuum()
      assert Indexer.posts_planned() == 0
    end

    test "increments on each create_post call", %{users_csv: users_csv} do
      Indexer.vacuum()
      Indexer.bulk_users(users_csv)

      Indexer.create_post(%{user_id: "1"})
      assert Indexer.posts_planned() == 1

      Indexer.create_post(%{user_id: "2"})
      assert Indexer.posts_planned() == 2
    end

    test "resets to 0 after vacuum", %{users_csv: users_csv} do
      Indexer.bulk_users(users_csv)
      Indexer.create_post(%{user_id: "1"})
      assert Indexer.posts_planned() > 0

      Indexer.vacuum()
      assert Indexer.posts_planned() == 0
    end
  end

  describe "posts_created/0" do
    test "returns 0 initially" do
      assert Indexer.posts_created() == 0
    end

    test "returns the number of posts in the database", %{users_csv: users_csv} do
      Indexer.bulk_users(users_csv)

      Indexer.create_post(%{user_id: "1"})
      Indexer.create_post(%{user_id: "2"})

      assert Indexer.posts_created() == 2
    end

    test "matches posts_planned when all posts succeed", %{users_csv: users_csv} do
      Indexer.vacuum()
      Indexer.bulk_users(users_csv)

      Indexer.create_post(%{user_id: "1"})
      Indexer.create_post(%{user_id: "2"})
      Indexer.create_post(%{user_id: "3"})

      assert Indexer.posts_planned() == Indexer.posts_created()
    end

    test "resets to 0 after vacuum", %{users_csv: users_csv} do
      Indexer.bulk_users(users_csv)
      Indexer.create_post(%{user_id: "1"})
      assert Indexer.posts_created() > 0

      Indexer.vacuum()
      assert Indexer.posts_created() == 0
    end
  end

  defp users_csv do
    """
    user_did,indexedAt,trustedVerifier
    1,20260303,false
    2,20260303,false
    3,20260303,false
    4,20260303,false
    """
  end

  defp edges_csv do
    """
    actor_id,subject_id
    2,1
    3,1
    4,1
    3,2
    """
  end

  defp posts_csv do
    """
    offset_ms,user_id
    0,1
    1000,2
    5000,1
    """
  end

  defp empty_posts_csv do
    "offset_ms,user_id\n"
  end
end
