defmodule DataplaneEx.CID do
  @moduledoc """
  `Ecto.Type` for `CID`
  """
  use Ecto.Type

  def type, do: :binary

  def cast(value) do
    cid_tag = 42
    %{tag: ^cid_tag, value: %{tag: :bytes, value: cid_binary}} = value
    {:ok, 0, cid} = CBOR.decode(cid_binary)

    {:ok, cid}
  end

  def load(data) do
    {:ok, CID.decode!(data)}
  end

  def dump(cid) do
    {:ok, CID.encode!(cid)}
  end
end
