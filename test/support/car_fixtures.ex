defmodule DataplaneEx.CARFixtures do
  @moduledoc false

  alias DASL.CAR.DRISL

  def build_car(record) do
    {:ok, {car, cid}} = DRISL.add_block(%DRISL{}, record)
    {:ok, car} = DRISL.add_root(car, cid)
    {:ok, bytes} = DRISL.encode(car)

    {car, cid, bytes}
  end
end
