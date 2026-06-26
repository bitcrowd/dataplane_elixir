defmodule DataplaneEx.CAR do
  @moduledoc """
  `Ecto.Type` for `CAR`
  """
  use Ecto.Type

  def type, do: :map

  def cast(%DASL.CAR.DRISL{} = car), do: {:ok, car}

  def cast(%CBOR.Tag{tag: :bytes, value: bytes}) do
    cast(bytes)
  end

  def cast(bytes) do
    case DASL.CAR.DRISL.decode(bytes) do
      {:ok, car} -> {:ok, car}
      {:error, _section, _reason} -> :error
    end
  end

  def load(data) do
    {:ok, data}
  end

  def dump(car) do
    {:ok, car}
  end
end
