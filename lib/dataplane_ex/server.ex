defmodule DataplaneEx.Server do
  @moduledoc """
  Dataplane server interface
  """

  @type user_id :: String.t()
  @type timeline_request :: {user_id(), limit :: pos_integer(), cursor :: term()}
  @type timeline_entry :: map()
  @type timeline_response :: {:ok, [timeline_entry()]} | {:error, term()}

  @callback get_timeline(timeline_request()) :: [timeline_entry()]

  @spec get_timeline(timeline_request()) :: timeline_response()
  def get_timeline({user_id, _limit, _cursor} = request) do
    :telemetry.span([:dataplane_ex, :get_timeline], %{user_id: user_id}, fn ->
      result = server().get_timeline(request)

      {{:ok, result}, %{rows: length(result)}}
    end)
  end

  defp server do
    Application.fetch_env!(:dataplane_ex, :server)
  end
end
