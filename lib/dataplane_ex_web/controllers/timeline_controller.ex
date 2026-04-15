defmodule DataplaneExWeb.TimelineController do
  use DataplaneExWeb, :controller

  alias DataplaneEx.Server

  def show(conn, params) do
    with {:ok, actor_id} <- parse_actor_did(params["actor_did"]),
         {:ok, limit} <- parse_limit(params["limit"]),
         {:ok, posts} <- Server.get_timeline({actor_id, limit, params["cursor"]}) do
      json(conn, %{"items" => posts})
    else
      {:error, :invalid_actor_did} ->
        conn
        |> put_status(:bad_request)
        |> json(%{"error" => "invalid actor_did"})

      {:error, :invalid_limit} ->
        conn
        |> put_status(:bad_request)
        |> json(%{"error" => "invalid limit"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{"error" => inspect(reason)})
    end
  end

  defp parse_actor_did(nil), do: {:error, :invalid_actor_did}

  defp parse_actor_did(actor_did) do
    case Integer.parse(actor_did) do
      {user_id, ""} when user_id > 0 ->
        {:ok, user_id}

      _ ->
        case Regex.run(~r/(\d+)$/, actor_did, capture: :all_but_first) do
          [user_id] -> {:ok, String.to_integer(user_id)}
          _ -> {:error, :invalid_actor_did}
        end
    end
  end

  defp parse_limit(nil), do: {:ok, 50}

  defp parse_limit(limit) do
    case Integer.parse(limit) do
      {parsed_limit, ""} when parsed_limit > 0 -> {:ok, parsed_limit}
      _ -> {:error, :invalid_limit}
    end
  end
end
