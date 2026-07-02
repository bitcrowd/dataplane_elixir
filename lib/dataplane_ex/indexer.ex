defmodule DataplaneEx.Indexer do
  @moduledoc """
  ETS implementation of the Dataplane Indexer.

  Stores the social graph, posts, and feeds in six named ETS tables:

    - `:social_graph_users`           — `:set` of `{user_id}`
    - `:social_graph_followers`        — `:duplicate_bag` of `{subject_id, actor_id}`
    - `:social_graph_following`        — `:duplicate_bag` of `{actor_id, subject_id}`
    - `:social_graph_posts`            — `:set` of `{post_id, author_id}` (`:public`, concurrent writes, concurrent reads)
    - `:social_graph_feeds`            — `:duplicate_bag` of `{user_id, post_id}` (`:public`, concurrent writes)
    - `:social_graph_celebrity_posts`  — `:duplicate_bag` of `{author_id, post_id}` (`:public`, concurrent writes)

  The social graph tables are `:protected` (owner writes, everyone reads).
  The posts table is `:public` with `write_concurrency: :auto` so that
  Server workers can insert posts without going through the GenServer.

  Post IDs are generated via an `:atomics` counter published in
  `:persistent_term` for lock-free access from any process.
  """
  use GenServer
  alias DataplaneEx.Progress
  require Logger

  @users_table :social_graph_users
  @followers_table :social_graph_followers
  @following_table :social_graph_following
  @posts_table :social_graph_posts
  @feeds_table :social_graph_feeds
  @celebrity_posts_table :social_graph_celebrity_posts
  @post_id_counter_key :social_graph_post_id_counter
  @posts_planned_counter_key :social_graph_posts_planned_counter

  @supported_options [:fan_out_limit]
  @config_key :indexer_ets_config

  @type user_id :: String.t()
  @type post_id :: pos_integer()
  @type source :: Enumerable.t() | String.t()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  defp fan_out_limit do
    case :persistent_term.get(@config_key, nil) do
      %{fan_out_limit: limit} -> limit
      _ -> :infinity
    end
  end

  @spec bulk_users(source(), keyword()) :: :ok
  def bulk_users(source, opts \\ []) do
    GenServer.call(__MODULE__, {:bulk_users, source, opts}, :infinity)
  end

  @spec bulk_follows(source(), keyword()) :: :ok
  def bulk_follows(source, opts \\ []) do
    GenServer.call(__MODULE__, {:bulk_follows, source, opts}, :infinity)
  end

  @spec bulk_load_posts(source(), keyword()) :: :ok
  def bulk_load_posts(source, opts \\ []) do
    GenServer.call(__MODULE__, {:bulk_load_posts, source, opts}, :infinity)
  end

  @spec bulk_users_from_file(Path.t(), keyword()) :: :ok
  def bulk_users_from_file(path, opts \\ []) do
    path
    |> File.stream!()
    |> bulk_users(Keyword.put_new(opts, :total, Progress.total_from_file(path)))
  end

  @spec bulk_follows_from_file(Path.t(), keyword()) :: :ok
  def bulk_follows_from_file(path, opts \\ []) do
    path
    |> File.stream!()
    |> bulk_follows(Keyword.put_new(opts, :total, Progress.total_from_file(path)))
  end

  @spec bulk_load_posts_from_file(Path.t(), keyword()) :: :ok
  def bulk_load_posts_from_file(path, opts \\ []) do
    path
    |> File.stream!()
    |> bulk_load_posts(Keyword.put_new(opts, :total, Progress.total_from_file(path)))
  end

  @spec vacuum() :: :ok
  def vacuum do
    GenServer.call(__MODULE__, :vacuum)
  end

  @spec count_users() :: non_neg_integer()
  def count_users do
    :ets.info(@users_table, :size)
  end

  @spec count_follows() :: non_neg_integer()
  def count_follows do
    :ets.info(@following_table, :size)
  end

  @spec followers(user_id()) :: [user_id()]
  def followers(user_id) do
    @followers_table
    |> :ets.lookup(user_id)
    |> Enum.map(&elem(&1, 1))
  end

  @spec create_post(%{required(:user_id) => user_id()}) :: :ok
  def create_post(%{user_id: user_id}) do
    :atomics.add(:persistent_term.get(@posts_planned_counter_key), 1, 1)
    post_id = next_post_id()
    insert_post(post_id, user_id)
    :ok
  end

  @spec toggle_follow(%{required(:actor_id) => user_id(), required(:subject_id) => user_id()}) ::
          :ok
  def toggle_follow(%{actor_id: actor_id, subject_id: subject_id}) do
    do_toggle_follow(actor_id, subject_id)
    :ok
  end

  defp do_toggle_follow(actor_id, subject_id) do
    pair = {actor_id, subject_id}

    exists? =
      @following_table
      |> :ets.lookup(actor_id)
      |> Enum.any?(fn entry -> entry == pair end)

    if exists? do
      :ets.delete_object(@following_table, pair)
      :ets.delete_object(@followers_table, {subject_id, actor_id})
    else
      :ets.insert(@following_table, pair)
      :ets.insert(@followers_table, {subject_id, actor_id})
    end
  end

  @spec posts_planned() :: non_neg_integer()
  def posts_planned do
    :atomics.get(:persistent_term.get(@posts_planned_counter_key), 1)
  end

  @spec posts_created() :: non_neg_integer()
  def posts_created do
    :ets.info(@posts_table, :size)
  end

  @spec following(user_id()) :: [user_id()]
  def following(user_id) do
    @following_table
    |> :ets.lookup(user_id)
    |> Enum.map(&elem(&1, 1))
  end

  @spec user_exists?(user_id()) :: boolean()
  def user_exists?(user_id) do
    :ets.member(@users_table, user_id)
  end

  @spec next_post_id() :: post_id()
  def next_post_id do
    :atomics.add_get(:persistent_term.get(@post_id_counter_key), 1, 1)
  end

  @doc """
  Insert a post and fan it out to the feeds of all the author's followers.
  """
  @spec insert_post(post_id(), user_id()) :: :ok
  def insert_post(post_id, author_id) do
    :ets.insert(@posts_table, {post_id, author_id})

    follower_entries = :ets.lookup(@followers_table, author_id)
    limit = fan_out_limit()

    if limit == :infinity or length(follower_entries) <= limit do
      Enum.each(follower_entries, fn {_subject, follower_id} ->
        :ets.insert(@feeds_table, {follower_id, post_id})
      end)
    else
      :ets.insert(@celebrity_posts_table, {author_id, post_id})
    end

    :ok
  end

  @spec insert_feed_entry(user_id(), post_id()) :: :ok
  def insert_feed_entry(user_id, post_id) do
    :ets.insert(@feeds_table, {user_id, post_id})
    :ok
  end

  @doc """
  Return the list of post IDs in a user's feed.
  """
  @spec get_timeline(user_id()) :: [post_id()]
  def get_timeline(user_id) do
    fan_out_posts =
      @feeds_table
      |> :ets.lookup(user_id)
      |> Enum.map(&elem(&1, 1))

    celebrity_posts =
      @following_table
      |> :ets.lookup(user_id)
      |> Enum.flat_map(fn {_actor, followed_id} ->
        :ets.lookup(@celebrity_posts_table, followed_id)
      end)
      |> Enum.map(&elem(&1, 1))

    fan_out_posts ++ celebrity_posts
  end

  def users_table, do: @users_table
  def followers_table, do: @followers_table
  def following_table, do: @following_table
  def posts_table, do: @posts_table
  def feeds_table, do: @feeds_table
  def celebrity_posts_table, do: @celebrity_posts_table

  @impl GenServer
  def init(opts) do
    opts = Keyword.validate!(opts, @supported_options)

    Phoenix.PubSub.subscribe(DataplaneEx.PubSub, "firehose")

    :persistent_term.put(@config_key, Map.new(opts))

    :ets.new(@users_table, [:set, :named_table, :protected, read_concurrency: true])

    :ets.new(@followers_table, [
      :duplicate_bag,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    :ets.new(@following_table, [
      :duplicate_bag,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    :ets.new(@posts_table, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true,
      decentralized_counters: true
    ])

    :ets.new(@feeds_table, [
      :duplicate_bag,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true,
      decentralized_counters: true
    ])

    :ets.new(@celebrity_posts_table, [
      :duplicate_bag,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true,
      decentralized_counters: true
    ])

    counter = :atomics.new(1, signed: false)
    :persistent_term.put(@post_id_counter_key, counter)

    planned_counter = :atomics.new(1, signed: false)
    :persistent_term.put(@posts_planned_counter_key, planned_counter)

    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:bulk_users, source, opts}, _from, state) do
    total = Progress.total_from_source(source, opts)

    source
    |> DataplaneEx.CSV.parse_users()
    |> Progress.each_with_progress(total, "Loading users", fn user_id ->
      :ets.insert(@users_table, {user_id})
    end)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:bulk_follows, source, opts}, _from, state) do
    total = Progress.total_from_source(source, opts)

    source
    |> DataplaneEx.CSV.parse_edges()
    |> Progress.each_with_progress(total, "Loading follows", fn {actor_id, subject_id} ->
      :ets.insert(@followers_table, {subject_id, actor_id})
      :ets.insert(@following_table, {actor_id, subject_id})
    end)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:bulk_load_posts, source, opts}, _from, state) do
    total = Progress.total_from_source(source, opts)

    source
    |> DataplaneEx.CSV.parse_posts()
    |> Progress.each_with_progress(total, "Loading posts", fn {_offset_ms, user_id} ->
      insert_post(next_post_id(), user_id)
    end)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:vacuum, _from, state) do
    :ets.delete_all_objects(@users_table)
    :ets.delete_all_objects(@followers_table)
    :ets.delete_all_objects(@following_table)
    :ets.delete_all_objects(@posts_table)
    :ets.delete_all_objects(@feeds_table)
    :ets.delete_all_objects(@celebrity_posts_table)
    :atomics.put(:persistent_term.get(@post_id_counter_key), 1, 0)
    :atomics.put(:persistent_term.get(@posts_planned_counter_key), 1, 0)

    {:reply, :ok, state}
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
        Logger.debug("unhandled commit event: #{inspect(event)}")
        :ok
    end
  end

  defp index_event(event) do
    Logger.debug("unhandled event: #{inspect(event)}")
    :ok
  end
end
