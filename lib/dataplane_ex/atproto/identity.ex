defmodule DataplaneEx.ATProto.Identity do
  import Ecto.Changeset
  use Ecto.Schema

  alias DataplaneEx.ATProto.Identity

  # spec: https://atproto.com/specs/sync#identity-events
  @primary_key false
  embedded_schema do
    field :seq, :integer
    field :did, :string
    field :time, :utc_datetime_usec
    field :handle, :string
  end

  @required_attrs [:seq, :did, :time]

  @attrs @required_attrs ++ [:handle]

  @doc false
  def changeset(%Identity{} = identity, attrs) do
    identity
    |> cast(attrs, @attrs)
    |> validate_required(@required_attrs)
  end

  def to_event(%Identity{} = identity) do
    %{did: did, seq: seq, handle: handle, time: time} = identity

    kind = :identity
    event_time = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

    %{
      did: did,
      time_us: event_time,
      kind: kind,
      identity: %{
        did: did,
        handle: handle,
        seq: seq,
        time: time
      }
    }
  end
end
