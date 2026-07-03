defmodule DataplaneEx.CARTest do
  use ExUnit.Case, async: true
  alias DataplaneEx.CAR

  test "casts CBOR byte payloads into decoded DASL DRISL CARs" do
    record = %{"$type" => "app.bsky.feed.post", "text" => "hello"}
    {:ok, {car, cid}} = DASL.CAR.DRISL.add_block(%DASL.CAR.DRISL{}, record)
    {:ok, car} = DASL.CAR.DRISL.add_root(car, cid)
    {:ok, bytes} = DASL.CAR.DRISL.encode(car)

    assert {:ok, decoded} = CAR.cast(%CBOR.Tag{tag: :bytes, value: bytes})
    assert %DASL.CAR.DRISL{} = decoded
    assert decoded.roots == [cid]
    assert decoded.blocks[cid] == record
  end

  test "accepts already decoded DASL DRISL CARs" do
    car = %DASL.CAR.DRISL{}

    assert CAR.cast(car) == {:ok, car}
  end

  test "rejects invalid CAR byte payloads" do
    assert CAR.cast(%CBOR.Tag{tag: :bytes, value: "not a car"}) == :error
  end
end
