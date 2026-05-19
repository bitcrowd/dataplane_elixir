defmodule DataplaneEx.CAR do
  @moduledoc """
  `Ecto.Type` for `CAR`
  """
  use Ecto.Type

  def type, do: :map

  def cast(%DASL.CAR.DRISL{} = car), do: {:ok, car}

  def cast(value) do
    %{tag: :bytes, value: bytes} = value

    case DASL.CAR.DRISL.decode(bytes) do
      {:ok, car} -> {:ok, car}
      {:error, _reason} -> :error
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
