defmodule DataplaneEx.ATProto.Event do
  @moduledoc """
  Decoding ATProto events.
  """

  alias DataplaneEx.ATProto.{Account, Commit, Identity}
  alias Ecto.Changeset

  require Logger

  def decode(event) when is_binary(event) do
    case decode(event, []) do
      {:ok, [%{"t" => "#commit"} | _rest] = event} -> decode_commit(event)
      {:ok, [%{"t" => "#identity"} | _rest] = event} -> decode_identity(event)
      {:ok, [%{"t" => "#account"} | _rest] = event} -> decode_account(event)
      {:ok, [%{"t" => "#error"} | _rest] = event} -> decode_error(event)
    end
  end

  defp decode("", decoded_acc) do
    {:ok, Enum.reverse(decoded_acc)}
  end

  defp decode(binary, decoded_acc) do
    case CBOR.decode(binary) do
      {:ok, decoded, rest} ->
        decode(rest, [decoded | decoded_acc])

      {:error, error} ->
        Logger.error("CBOR decode failed: #{inspect(error)}")
        {:ok, []}
    end
  end

  defp decode_commit(event) do
    [_op, event] = event

    changeset = Commit.changeset(%Commit{}, event)

    case Changeset.apply_action(changeset, :validate) do
      {:ok, commit} ->
        Commit.to_event(commit)

      {:error, changeset} ->
        Logger.error("invalid event: #{inspect(changeset.errors)}")
        []
    end
  end

  defp decode_identity(event) do
    [_op, event] = event

    changeset = Identity.changeset(%Identity{}, event)

    case Changeset.apply_action(changeset, :validate) do
      {:ok, identity} ->
        Identity.to_event(identity)

      {:error, changeset} ->
        Logger.error("invalid event: #{inspect(changeset.errors)}")
        []
    end
  end

  defp decode_account(event) do
    [_op, event] = event

    changeset = Account.changeset(%Account{}, event)

    case Changeset.apply_action(changeset, :validate) do
      {:ok, account} ->
        Account.to_event(account)

      {:error, changeset} ->
        Logger.error("invalid event: #{inspect(changeset.errors)}")
        []
    end
  end

  defp decode_error(event), do: event
end
