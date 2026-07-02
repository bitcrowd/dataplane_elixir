defmodule DataplaneEx.ATProto.Commit do
  use Ecto.Schema

  import Ecto.Changeset

  # spec: https://atproto.com/specs/sync#commit-events
  @primary_key false
  embedded_schema do
    field :seq, :integer
    field :repo, :string
    field :time, :utc_datetime_usec
    field :rev, :string
    field :since, :string
    field :commit, DataplaneEx.CID
    field :tooBig, :boolean
    field :blocks, DataplaneEx.CAR
    embeds_many :ops, DataplaneEx.Op
    field :blobs, {:array, :binary}
  end

  @required_attrs [:seq, :repo, :time, :rev, :commit, :tooBig, :blocks, :blobs]

  @attrs @required_attrs ++ [:since]

  @doc false
  def changeset(%__MODULE__{} = commit, attrs) do
    commit
    |> cast(attrs, @attrs)
    |> cast_embed(:ops, required: true)
    |> validate_required(@required_attrs)
  end

  def to_event(%__MODULE__{} = commit) do
    for op <- commit.ops do
      to_event(op, commit)
    end
  end

  defp to_event(%{action: "delete"} = op, commit) do
    %{repo: did, rev: rev} = commit
    kind = :commit
    event_time = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

    operation = op.action

    [collection, rkey] = Path.split(op.path)

    %{
      did: did,
      time_us: event_time,
      kind: kind,
      commit: %{
        rev: rev,
        operation: operation,
        collection: collection,
        rkey: rkey
      }
    }
  end

  defp to_event(op, commit) do
    %{repo: did, rev: rev, blocks: blocks} = commit
    kind = :commit
    event_time = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

    operation = op.action
    cid = op.cid

    [collection, rkey] = Path.split(op.path)

    record = Map.get(blocks.blocks, cid, %{})
    cid = DASL.CID.encode(cid)

    %{
      did: did,
      time_us: event_time,
      kind: kind,
      commit: %{
        rev: rev,
        operation: operation,
        collection: collection,
        rkey: rkey,
        record: Map.take(record, ["$type", "createdAt", "subject"]),
        cid: cid
      }
    }
  end
end
