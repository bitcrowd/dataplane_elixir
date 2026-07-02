defmodule DataplaneEx.Op do
  use Ecto.Schema

  import Ecto.Changeset

  alias DataplaneEx.CID

  embedded_schema do
    field :action, :string
    field :cid, CID
    field :path, :string
  end

  @attrs [:action, :cid, :path]

  def changeset(%__MODULE__{} = op, attrs) do
    changeset = cast(op, attrs, @attrs)

    case get_change(changeset, :action) do
      "delete" -> validate_required(changeset, [:action, :path])
      _else -> validate_required(changeset, [:action, :cid, :path])
    end
  end
end
