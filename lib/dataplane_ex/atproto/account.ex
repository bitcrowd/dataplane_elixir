defmodule DataplaneEx.ATProto.Account do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  # spec: https://atproto.com/specs/sync#account-events
  @primary_key false

  @required_attrs [:seq, :did, :time, :active]
  @attrs @required_attrs ++ [:status]

  embedded_schema do
    field :seq, :integer
    field :did, :string
    field :time, :utc_datetime_usec
    field :active, :boolean
    field :status, Ecto.Enum, values: [:takendown, :suspended, :deleted, :deactivated]
  end

  def changeset(%__MODULE__{} = account, attrs) do
    account
    |> cast(attrs, @attrs)
    |> validate_required(@required_attrs)
  end

  def to_event(%__MODULE__{} = account) do
    %{did: did, seq: seq, active: active, time: time} = account

    %{
      did: did,
      time_us: DateTime.utc_now() |> DateTime.to_unix(:microsecond),
      kind: :account,
      account: %{
        active: active,
        did: did,
        seq: seq,
        time: time
      }
    }
  end
end
