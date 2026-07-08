defmodule DataplaneEx.CommitFixtures do
  @moduledoc false

  import DataplaneEx.CARFixtures
  alias DASL.CAR.DRISL
  alias DASL.CID

  @doc """
  Encodes a `#commit` firehose frame with a single op whose record lives in the commit's CAR blocks.
  """
  def commit_frame(repo, collection, record, opts \\ []) do
    rkey = Keyword.get(opts, :rkey, "abc123")
    action = Keyword.get(opts, :action, "create")

    commit_cid = CID.compute(repo <> collection <> rkey, :drisl)

    {op, car_bytes} =
      case action do
        "delete" ->
          {:ok, empty_car_bytes} = DRISL.encode(%DRISL{})
          {%{"action" => "delete", "path" => "#{collection}/#{rkey}"}, empty_car_bytes}

        _ ->
          {_car, cid, bytes} = build_car(record)
          op = %{"action" => action, "cid" => CID.to_cbor(cid), "path" => "#{collection}/#{rkey}"}
          {op, bytes}
      end

    payload = %{
      "seq" => 1,
      "repo" => repo,
      "time" => "2026-01-01T00:00:00.000Z",
      "rev" => "3lxyz",
      "commit" => CID.to_cbor(commit_cid),
      "tooBig" => false,
      "blocks" => car_bytes,
      "ops" => [op],
      "blobs" => []
    }

    CBOR.encode(%{"op" => 1, "t" => "#commit"}) <> CBOR.encode(payload)
  end
end
