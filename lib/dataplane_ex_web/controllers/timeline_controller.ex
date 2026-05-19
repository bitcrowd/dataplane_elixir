defmodule DataplaneExWeb.TimelineController do
  use DataplaneExWeb, :controller

  alias DataplaneEx.Server

  def timeline(conn, params) do
    %{"actor_did" => actor_did, "limit" => limit} = params

    case Server.get_timeline({actor_did, limit, params["cursor"]}) do
      {:ok, posts} ->
        json(conn, %{"items" => posts})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{"error" => inspect(reason)})
    end
  end
end
