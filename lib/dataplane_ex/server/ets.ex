defmodule DataplaneEx.Server.ETS do
  @moduledoc """
  ETS-backed implementation of the Dataplane Server.

  Delegates to `DataplaneEx.Indexer.ETS` for timeline reads.
  Emits the same telemetry spans as the Postgres implementation so metrics
  are comparable.
  """
  @behaviour DataplaneEx.Server

  alias DataplaneEx.Indexer.ETS, as: Indexer

  @impl true
  def get_timeline({user_id, limit, _cursor}) do
    :telemetry.span([:dataplane_ex, :get_timeline], %{user_id: user_id}, fn ->
      result =
        user_id
        |> Indexer.get_timeline()
        |> Enum.sort(:desc)
        |> Enum.take(limit)
        |> Enum.map(fn post_id -> %{id: post_id} end)

      {{:ok, result}, %{rows: length(result)}}
    end)
  end
end
