defmodule DataplaneEx.CID do
  @moduledoc """
  `Ecto.Type` for `CID`
  """
  use Ecto.Type

  def type, do: :binary

  def cast(%DASL.CID{} = cid), do: {:ok, cid}

  def cast(value) do
    case DASL.CID.from_cbor(value) do
      {:ok, cid} -> {:ok, cid}
      {:error, _reason} -> :error
    end
  end

  def load(data) when is_binary(data) do
    case DASL.CID.from_bytes(data) do
      {:ok, cid} -> {:ok, cid}
      {:error, _reason} -> :error
    end
  end

  def load(%DASL.CID{} = cid) do
    {:ok, cid}
  end

  def dump(%DASL.CID{bytes: bytes}) do
    {:ok, bytes}
  end
end
