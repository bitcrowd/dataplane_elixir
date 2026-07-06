defmodule DataplaneEx.CARTest do
  use ExUnit.Case, async: true
  alias DASL.CAR.DRISL
  alias DataplaneEx.CAR

  test "casts CBOR byte payloads into decoded DASL DRISL CARs" do
    record = %{"$type" => "app.bsky.feed.post", "text" => "hello"}
    {:ok, {car, cid}} = DRISL.add_block(%DRISL{}, record)
    {:ok, car} = DRISL.add_root(car, cid)
    {:ok, bytes} = DRISL.encode(car)

    assert {:ok, decoded} = CAR.cast(%CBOR.Tag{tag: :bytes, value: bytes})
    assert %DRISL{} = decoded
    assert decoded.roots == [cid]
    assert decoded.blocks[cid] == record
  end

  test "accepts already decoded DASL DRISL CARs" do
    car = %DRISL{}

    assert CAR.cast(car) == {:ok, car}
  end

  test "rejects invalid CAR byte payloads" do
    assert CAR.cast(%CBOR.Tag{tag: :bytes, value: "not a car"}) == :error
  end
end
