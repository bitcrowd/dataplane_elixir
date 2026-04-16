defmodule DataplaneEx.ATProto.Commit do
  import Ecto.Changeset
  use Ecto.Schema

  alias DataplaneEx.ATProto.Commit

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
  def changeset(%Commit{} = commit, attrs) do
    commit
    |> cast(attrs, @attrs)
    |> cast_embed(:ops, required: true)
    |> validate_required(@required_attrs)
  end

  def to_jetstream(%Commit{} = commit) do
    for op <- commit.ops do
      to_jetstream(op, commit)
    end
  end

  defp to_jetstream(%{action: "delete"} = op, commit) do
    %{repo: did, rev: rev} = commit
    kind = :commit
    jetstream_time = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

    operation = op.action

    [collection, rkey] = Path.split(op.path)

    %{
      did: did,
      time_us: jetstream_time,
      kind: kind,
      commit: %{
        rev: rev,
        operation: operation,
        collection: collection,
        rkey: rkey
      }
    }
  end

  defp to_jetstream(op, commit) do
    %{repo: did, rev: rev, blocks: blocks} = commit
    kind = :commit
    jetstream_time = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

    operation = op.action
    cid = op.cid

    [collection, rkey] = Path.split(op.path)

    record = CAR.Archive.get_block(blocks, cid)

    # TODO: fix encoding to follow https://atproto.com/specs/data-model#link-and-cid-formats
    cid = CID.cid!(cid) |> CID.encode!()

    %{
      did: did,
      time_us: jetstream_time,
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
