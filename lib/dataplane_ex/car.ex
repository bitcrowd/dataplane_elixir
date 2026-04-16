defmodule DataplaneEx.CAR do
  @moduledoc """
  `Ecto.Type` for `CAR`
  """
  use Ecto.Type

  def type, do: :map

  def cast(value) do
    %{tag: :bytes, value: bytes} = value
    {:ok, car} = CAR.decode(bytes)

    {:ok, car}
  end

  def load(data) do
    {:ok, data}
  end

  def dump(car) do
    {:ok, car}
  end
end
