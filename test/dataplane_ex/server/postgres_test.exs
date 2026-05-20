defmodule DataplaneEx.Server.PostgresTest do
  use DataplaneEx.DataCase

  alias DataplaneEx.Server.Postgres

  setup do
    Repo.insert_all("users", [%{id: "1"}, %{id: "2"}, %{id: "3"}, %{id: "4"}])

    Repo.insert_all("follows", [
      %{actor_id: "1", subject_id: "2"},
      %{actor_id: "1", subject_id: "3"}
    ])

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    earlier = NaiveDateTime.add(now, -60)
    earliest = NaiveDateTime.add(now, -120)

    {4, posts} =
      Repo.insert_all(
        "posts",
        [
          %{author_id: "2", inserted_at: earliest},
          %{author_id: "3", inserted_at: earlier},
          %{author_id: "2", inserted_at: now},
          %{author_id: "4", inserted_at: now}
        ],
        returning: [:id, :author_id]
      )

    by_author = Enum.group_by(posts, & &1.author_id)

    %{
      now: now,
      earlier: earlier,
      earliest: earliest,
      posts_by_author: by_author
    }
  end

  test "returns posts from followed users ordered by inserted_at desc", ctx do
    timeline = Postgres.get_timeline({"1", 10, nil})

    followed_ids =
      (ctx.posts_by_author["2"] ++ ctx.posts_by_author["3"])
      |> Enum.map(& &1.id)
      |> MapSet.new()

    returned_ids = Enum.map(timeline, & &1.id)

    assert MapSet.new(returned_ids) == followed_ids
    assert returned_ids == Enum.sort(returned_ids, :desc)
  end

  test "excludes posts from unfollowed users" do
    timeline = Postgres.get_timeline({"1", 10, nil})
    author_ids = Enum.map(timeline, & &1.author_id) |> Enum.uniq()

    refute "4" in author_ids
  end

  test "respects the limit parameter" do
    timeline = Postgres.get_timeline({"1", 2, nil})

    assert length(timeline) == 2
  end

  test "returns empty list for user with no follows" do
    timeline = Postgres.get_timeline({"4", 10, nil})
    assert timeline == []
  end

  test "returns empty list for user with no posts in followed accounts" do
    Repo.insert_all("users", [%{id: "5"}])
    Repo.insert_all("follows", [%{actor_id: "5", subject_id: "4"}])
    Repo.delete_all(from(p in "posts", where: p.author_id == "4"))

    timeline = Postgres.get_timeline({"5", 10, nil})
    assert timeline == []
  end
end
