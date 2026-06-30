defmodule DataplaneEx.ServerTest do
  use ExUnit.Case, async: false

  alias DataplaneEx.Server
  alias DataplaneEx.Indexer

  setup do
    did1 = "did:plc:firesim1"
    did2 = "did:plc:firesim2"
    did3 = "did:plc:firesim3"
    did4 = "did:plc:firesim4"

    start_supervised!(Indexer)

    Indexer.bulk_users(users_csv(did1, did2, did3, did4))
    Indexer.bulk_follows(edges_csv(did1, did2, did3, did4))

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
end
