defmodule DataplaneEx.CARTest do
  use ExUnit.Case, async: true
  import DataplaneEx.CARFixtures
  alias DASL.CAR.DRISL
  alias DataplaneEx.CAR

  test "casts CBOR byte payloads into decoded DASL DRISL CARs" do
    record = %{"$type" => "app.bsky.feed.post", "text" => "hello"}
    {_car, cid, bytes} = build_car(record)

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

  test "casts raw CAR bytes without a CBOR tag wrapper" do
    record = %{"$type" => "app.bsky.feed.post", "text" => "hello"}
    {_car, cid, bytes} = build_car(record)

    assert {:ok, decoded} = CAR.cast(bytes)
    assert %DRISL{} = decoded
    assert decoded.roots == [cid]
  end

  test "load/1 returns the CAR unchanged" do
    car = %DRISL{}

    assert CAR.load(car) == {:ok, car}
  end

  test "dump/1 returns the CAR unchanged" do
    car = %DRISL{}

    assert CAR.dump(car) == {:ok, car}
  end

  test "type/0 returns :map" do
    assert CAR.type() == :map
  end
end
