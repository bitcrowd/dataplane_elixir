defmodule DataplaneEx.Server.Postgres do
  @moduledoc """
  Postgres-backed server queries for timeline reads.
  """

  @behaviour DataplaneEx.Server

  import Ecto.Query

  alias DataplaneEx.Repo

  @impl true
  def get_timeline({user_id, limit, _cursor}) do
    query =
      from p in "posts",
        join: f in "follows",
        on: f.subject_id == p.author_id,
        where: f.actor_id == ^user_id,
        order_by: [desc: p.inserted_at],
        limit: ^limit,
        select: %{id: p.id, author_id: p.author_id, inserted_at: p.inserted_at}

    Repo.all(query)
  end
end
