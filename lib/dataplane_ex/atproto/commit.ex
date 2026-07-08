defmodule DataplaneEx.ATProto.Commit do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  # spec: https://atproto.com/specs/sync#commit-events
  @primary_key false

  @required_attrs [:seq, :repo, :time, :rev, :commit, :tooBig, :blocks, :blobs]
  @attrs @required_attrs ++ [:since]

  embedded_schema do
    field :seq, :integer
    field :repo, :string
    field :time, :utc_datetime_usec
    field :rev, :string
    field :since, :string
    field :commit, DataplaneEx.CID
    field :tooBig, :boolean
    field :blocks, DataplaneEx.CAR
    field :blobs, {:array, :binary}

    embeds_many :ops, DataplaneEx.Op
  end

  def changeset(%__MODULE__{} = commit, attrs) do
    commit
    |> cast(attrs, @attrs)
    |> cast_embed(:ops, required: true)
    |> validate_required(@required_attrs)
  end

  def to_event(%__MODULE__{} = commit) do
    Enum.map(commit.ops, &to_event(&1, commit))
  end

  defp to_event(%{action: "delete"} = op, %{repo: did, rev: rev}) do
    [collection, rkey] = Path.split(op.path)

    %{
      did: did,
      time_us: time_us(),
      kind: :commit,
      commit: %{
        rev: rev,
        operation: op.action,
        collection: collection,
        rkey: rkey
      }
    }
  end

  defp to_event(op, %{repo: did, rev: rev, blocks: %{blocks: blocks}}) do
    cid = op.cid
    record = Map.get(blocks, cid, %{})
    [collection, rkey] = Path.split(op.path)

    %{
      did: did,
      time_us: time_us(),
      kind: :commit,
      commit: %{
        rev: rev,
        operation: op.action,
        collection: collection,
        rkey: rkey,
        record: Map.take(record, ["$type", "createdAt", "subject"]),
        cid: DASL.CID.encode(cid)
      }
    }
  end

  defp time_us, do: DateTime.utc_now() |> DateTime.to_unix(:microsecond)
end
