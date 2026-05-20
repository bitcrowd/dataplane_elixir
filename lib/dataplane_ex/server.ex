defmodule DataplaneEx.Server do
  @moduledoc """
  Behaviour defining the dataplane server interface.

  Implementations provide the actual data access layer — Postgres, ETS,
  in-memory, etc. The simulator calls into whichever implementation is
  configured, allowing apples-to-apples performance comparison.
  """

  @type user_id :: String.t()
  @type timeline_request :: {user_id(), limit :: pos_integer(), cursor :: term()}
  @type timeline_entry :: map()
  @type timeline_response :: {:ok, [timeline_entry()]} | {:error, term()}

  @callback get_timeline(timeline_request()) :: timeline_response()

  def get_timeline({user_id, _limit, _cursor} = request) do
    :telemetry.span([:dataplane_ex, :get_timeline], %{user_id: user_id}, fn ->
      result = server().get_timeline(request)

      {{:ok, result}, %{rows: length(result)}}
    end)
  end

  def server do
    Application.fetch_env!(:dataplane_ex, :server)
  end
end
