defmodule DataplaneEx.Server do
  @moduledoc """
  ETS-backed implementation of the Dataplane Server.
  """

  alias DataplaneEx.Indexer

  @type user_id :: String.t()
  @type timeline_request :: {user_id(), limit :: pos_integer(), cursor :: term()}
  @type timeline_entry :: map()
  @type timeline_response :: {:ok, [timeline_entry()]} | {:error, term()}

  @callback get_timeline(timeline_request()) :: [timeline_entry()]

  @spec get_timeline(timeline_request()) :: timeline_response()
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

  defp server do
    Application.fetch_env!(:dataplane_ex, :server)
  end
end
