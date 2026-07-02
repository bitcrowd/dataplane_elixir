defmodule DataplaneEx.CSVFixtures do
  @moduledoc false

  def users_csv(did1, did2, did3, did4) do
    """
    user_did,indexedAt,trustedVerifier
    #{did1},20260303,false
    #{did2},20260303,false
    #{did3},20260303,false
    #{did4},20260303,false
    """
  end

  def follows_csv(did1, did2, did3, did4) do
    """
    uri,cid,actor_did,subject_did
    at://something,bayfreixx,#{did2},#{did1}
    at://something,bayfreixx,#{did3},#{did1}
    at://something,bayfreixx,#{did4},#{did1}
    at://something,bayfreixx,#{did3},#{did2}
    """
  end

  def posts_csv(did1, did2) do
    """
    offset_ms,user_id
    0,#{did1}
    1000,#{did2}
    5000,#{did1}
    """
  end

  def empty_posts_csv do
    "offset_ms,user_id\n"
  end
end
