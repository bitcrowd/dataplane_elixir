defmodule DataplaneEx.CSVTest do
  use ExUnit.Case, async: true
  import DataplaneEx.TmpFileFixtures
  alias DataplaneEx.CSV

  test "parse_users/1 returns user DIDs and unquotes fields" do
    csv = """
    user_did,indexedAt,trustedVerifier
    "did:plc:alice",2026-01-01T00:00:00Z,false
    did:plc:bob,2026-01-01T00:00:00Z,false
    """

    assert Enum.to_list(CSV.parse_users(csv)) == ["did:plc:alice", "did:plc:bob"]
  end

  test "parse_users/1 accepts a stream of lines" do
    csv = "user_did,indexedAt,trustedVerifier\ndid:plc:alice,2026-01-01T00:00:00Z,false\n"

    result =
      csv
      |> String.splitter("\n", trim: false)
      |> CSV.parse_users()
      |> Enum.to_list()

    assert result == ["did:plc:alice"]
  end

  test "parse_edges/1 returns actor/subject pairs and skips blank lines" do
    csv = """
    uri,cid,actor_did,subject_did
    at://did:plc:bob/app.bsky.graph.follow/1,bafyre,did:plc:bob,did:plc:alice

    "at://did:plc:carol/app.bsky.graph.follow/2",bafyre,"did:plc:carol","did:plc:alice"
    """

    assert Enum.to_list(CSV.parse_edges(csv)) == [
             {"did:plc:bob", "did:plc:alice"},
             {"did:plc:carol", "did:plc:alice"}
           ]
  end

  test "parse_posts/1 returns offset/user tuples" do
    csv = """
    offset_ms,user_id
    0,did:plc:alice
    1000,did:plc:bob
    """

    assert Enum.to_list(CSV.parse_posts(csv)) == [{0, "did:plc:alice"}, {1000, "did:plc:bob"}]
  end

  describe "read_meta/1 and write_meta/2" do
    test "round-trips metadata through a companion .meta file" do
      path = tmp_path("csv_test")

      cleanup_meta(path)

      assert :ok = CSV.write_meta(path, %{total: 42})
      assert CSV.read_meta(path) == %{total: 42}
    end

    test "returns an empty map when no .meta file exists" do
      assert CSV.read_meta(tmp_path("csv_test")) == %{}
    end

    test "ignores malformed lines in a .meta file" do
      path = tmp_path("csv_test")

      cleanup_meta(path)
      File.write!(meta_path(path), "total: 42\nmalformed line without colon\n")

      assert CSV.read_meta(path) == %{total: 42}
    end
  end
end
