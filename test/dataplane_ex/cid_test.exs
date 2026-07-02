defmodule DataplaneEx.CIDTest do
  use ExUnit.Case, async: true
  alias DataplaneEx.CID

  test "casts DASL CID values from CBOR tag 42 links" do
    cid = DASL.CID.compute("hello world", :drisl)

    assert CID.cast(DASL.CID.to_cbor(cid)) == {:ok, cid}
  end

  test "loads and dumps DASL CIDs as raw bytes" do
    cid = DASL.CID.compute("hello world", :drisl)

    assert CID.dump(cid) == {:ok, cid.bytes}
    assert CID.load(cid.bytes) == {:ok, cid}
  end

  test "rejects invalid CID payloads" do
    assert CID.cast(%CBOR.Tag{tag: 1, value: "not a cid"}) == :error
    assert CID.load("not a cid") == :error
  end
end
