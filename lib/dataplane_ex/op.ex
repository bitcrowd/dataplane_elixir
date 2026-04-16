defmodule DataplaneEx.Op do
  import Ecto.Changeset
  use Ecto.Schema

  alias DataplaneEx.Op
  alias DataplaneEx.CID

  embedded_schema do
    field :action, :string
    field :cid, CID
    field :path, :string
  end

  @attrs [:action, :cid, :path]

  def changeset(%Op{} = op, attrs) do
    changeset = cast(op, attrs, @attrs)

    case get_change(changeset, :action) do
      "delete" -> validate_required(changeset, [:action, :path])
      _else -> validate_required(changeset, [:action, :cid, :path])
    end
  end
end
