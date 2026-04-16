defmodule DataplaneEx.Indexer.Postgres do
  @behaviour DataplaneEx.Indexer

  use GenServer

  require Logger
  import Ecto.Query

  alias DataplaneEx.{Progress, Repo}

  @supported_options MapSet.new([:batch_size])
  @config_key :indexer_postgres_config
  @default_batch_size 5_000
  @posts_planned_counter_key :indexer_postgres_posts_planned_counter

  defp write_repo do
    Application.get_env(:dataplane_ex, :write_repo, DataplaneEx.WriteRepo)
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    Phoenix.PubSub.subscribe(DataplaneEx.PubSub, "firehose")

    DataplaneEx.Indexer.validate_options!(opts, @supported_options)
    :persistent_term.put(@config_key, Map.new(opts))
    ensure_posts_planned_counter()
    DataplaneEx.Indexer.register_active(__MODULE__)

    {:ok, %{}}
  end

  defp ensure_posts_planned_counter do
    case :persistent_term.get(@posts_planned_counter_key, nil) do
      nil ->
        counter = :atomics.new(1, signed: false)
        :persistent_term.put(@posts_planned_counter_key, counter)

      _existing ->
        :ok
    end
  end

  defp batch_size do
    case :persistent_term.get(@config_key, nil) do
      %{batch_size: size} -> size
      _ -> @default_batch_size
    end
  end

  defp extract_first_column(source_path, dest_path, header, total) do
    dest = File.open!(dest_path, [:write, :raw])

    try do
      :file.write(dest, [header, ?\n])

      source_path
      |> File.stream!()
      |> Stream.drop(1)
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Progress.each_with_progress(total, "Extracting IDs", fn line ->
        id = line |> String.split(",", parts: 2) |> hd()
        :file.write(dest, [id, ?\n])
      end)
    after
      File.close(dest)
    end
  end

  @impl true
  def bulk_users(filepath) do
    total = DataplaneEx.CSV.read_meta(filepath)[:total] || 0
    tmp_path = Path.expand(filepath) <> ".ids_only.tmp"

    try do
      extract_first_column(filepath, tmp_path, "id", total)

      monitor = Progress.monitor_copy("COPY users")

      Ecto.Adapters.SQL.query!(
        write_repo(),
        "COPY users (id) FROM '#{tmp_path}' WITH (FORMAT csv, HEADER true)",
        [],
        timeout: :infinity
      )

      Progress.stop_monitor(monitor)
    after
      File.rm(tmp_path)
    end

    :ok
  end

  @impl true
  def bulk_follows(filepath) do
    abs_path = Path.expand(filepath)

    Logger.info("[bulk_follows] Dropping indexes...")

    Ecto.Adapters.SQL.query!(
      write_repo(),
      "DROP INDEX IF EXISTS follows_actor_id_subject_id_index",
      [],
      timeout: :infinity
    )

    Ecto.Adapters.SQL.query!(write_repo(), "DROP INDEX IF EXISTS follows_subject_id_index", [],
      timeout: :infinity
    )

    try do
      monitor = Progress.monitor_copy("COPY follows")

      Ecto.Adapters.SQL.query!(
        write_repo(),
        "COPY follows (actor_id, subject_id) FROM '#{abs_path}' WITH (FORMAT csv, HEADER true)",
        [],
        timeout: :infinity
      )

      Progress.stop_monitor(monitor)
    after
      monitor = Progress.monitor_create_index("Creating unique index (actor_id, subject_id)")

      Ecto.Adapters.SQL.query!(
        write_repo(),
        "CREATE UNIQUE INDEX follows_actor_id_subject_id_index ON follows (actor_id, subject_id)",
        [],
        timeout: :infinity
      )

      Progress.stop_monitor(monitor)

      monitor = Progress.monitor_create_index("Creating index (subject_id)")

      Ecto.Adapters.SQL.query!(
        write_repo(),
        "CREATE INDEX follows_subject_id_index ON follows (subject_id)",
        [],
        timeout: :infinity
      )

      Progress.stop_monitor(monitor)
    end

    :ok
  end

  @impl true
  def bulk_load_posts(filepath, opts \\ []) do
    time_offset_ms = Keyword.get(opts, :time_offset_ms, 0)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:millisecond)
    total = DataplaneEx.CSV.read_meta(filepath)[:total] || 0

    filepath
    |> DataplaneEx.CSV.parse_posts()
    |> Stream.map(fn {offset_ms, user_id} ->
      inserted_at = NaiveDateTime.add(now, time_offset_ms + offset_ms, :millisecond)
      %{author_id: user_id, inserted_at: inserted_at}
    end)
    |> Stream.chunk_every(batch_size())
    |> Progress.each_with_progress(
      total,
      "Loading posts",
      fn batch ->
        write_repo().insert_all("posts", batch)
      end,
      step: batch_size()
    )

    :ok
  end

  @impl true
  def vacuum do
    Ecto.Adapters.SQL.query!(write_repo(), "TRUNCATE posts, follows, users")
    ensure_posts_planned_counter()
    :atomics.put(:persistent_term.get(@posts_planned_counter_key), 1, 0)
    :ok
  end

  @impl true
  def count_users do
    Repo.aggregate("users", :count)
  end

  @impl true
  def count_follows do
    Repo.aggregate("follows", :count)
  end

  @impl true
  def followers(user_id) do
    from(f in "follows", where: f.subject_id == ^user_id, select: f.actor_id)
    |> Repo.all()
  end

  @impl true
  def following(user_id) do
    from(f in "follows", where: f.actor_id == ^user_id, select: f.subject_id)
    |> Repo.all()
  end

  @impl true
  def create_post(%{user_id: user_id}) do
    :atomics.add(:persistent_term.get(@posts_planned_counter_key), 1, 1)

    :telemetry.span([:dataplane_ex, :create_post], %{user_id: user_id}, fn ->
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      case write_repo().insert_all("posts", [%{author_id: user_id, inserted_at: now}]) do
        {count, _} when count > 0 -> {:ok, %{}}
      end
    end)
  end

  @impl true
  def toggle_follow(%{actor_id: actor_id, subject_id: subject_id}) do
    :telemetry.span(
      [:dataplane_ex, :toggle_follow],
      %{actor_id: actor_id, subject_id: subject_id},
      fn ->
        result =
          write_repo().transaction(fn ->
            deleted_count =
              from(f in "follows",
                where: f.actor_id == ^actor_id and f.subject_id == ^subject_id
              )
              |> write_repo().delete_all()
              |> elem(0)

            if deleted_count == 0 do
              write_repo().insert_all(
                "follows",
                [%{actor_id: actor_id, subject_id: subject_id}],
                on_conflict: :nothing,
                conflict_target: [:actor_id, :subject_id]
              )
            end
          end)
          |> case do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end

        {result, %{}}
      end
    )
  end

  @impl true
  def posts_planned do
    :atomics.get(:persistent_term.get(@posts_planned_counter_key), 1)
  end

  @impl true
  def posts_created do
    Repo.aggregate("posts", :count)
  end

  @impl GenServer
  def handle_info({:binary, binary}, state) do
    events =
      binary
      |> DataplaneEx.ATProto.Event.decode()
      |> List.wrap()

    Enum.each(events, &index_event/1)

    {:noreply, state}
  end

  defp index_event(%{kind: :commit} = event) do
    case event do
      %{did: did, commit: %{collection: "app.bsky.feed.post"}} ->
        create_post(%{user_id: did})

      %{did: did, commit: %{collection: "app.bsky.graph.follow", record: %{"subject" => subject}}} ->
        toggle_follow(%{actor_id: did, subject_id: subject})

      _other ->
        Logger.debug("unhandled commit event: #{event}")
        :ok
    end
  end

  defp index_event(event) do
    Logger.debug("unhandled event: #{event}")
    :ok
  end
end
