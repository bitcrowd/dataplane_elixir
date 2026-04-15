defmodule DataplaneEx.Indexer do
  @moduledoc """
  Behaviour defining the dataplane indexer interface.

  Implementations handle bulk data loading and cleanup — importing follow
  graphs, vacuuming tables, etc. The query path lives in `Dataplane.Server`.
  """

  @callback init() :: :ok | {:error, term()}
  @callback configure(opts :: keyword()) :: :ok
  @callback bulk_users(filepath :: String.t()) :: :ok | {:error, term()}
  @callback bulk_follows(filepath :: String.t()) :: :ok | {:error, term()}
  @callback bulk_load_posts(filepath :: String.t(), opts :: keyword()) :: :ok | {:error, term()}
  @callback vacuum() :: :ok
  @callback count_users() :: non_neg_integer()
  @callback count_follows() :: non_neg_integer()
  @callback followers(user_id :: pos_integer()) :: [pos_integer()]
  @callback following(user_id :: pos_integer()) :: [pos_integer()]
  @callback create_post(%{user_id: pos_integer()}) :: :ok | {:error, term()}
  @callback toggle_follow(%{actor_id: pos_integer(), subject_id: pos_integer()}) ::
              :ok | {:error, term()}
  @callback posts_planned() :: non_neg_integer()
  @callback posts_created() :: non_neg_integer()

  @active_indexer_key :dataplane_ex_active_indexer

  @doc """
  Register `module` as the active indexer so the telemetry poller can
  call `posts_planned/0` and `posts_created/0` without hard-coding the
  implementation.
  """
  def register_active(module) do
    :persistent_term.put(@active_indexer_key, module)
  end

  @doc "Return the currently registered indexer module, or `nil`."
  def active_indexer do
    :persistent_term.get(@active_indexer_key, nil)
  end

  @doc """
  Validate that all keys in `opts` are in the `supported` set.
  Raises `ArgumentError` listing any unsupported keys.
  """
  def validate_options!(opts, supported) do
    unsupported = opts |> Keyword.keys() |> Enum.reject(&MapSet.member?(supported, &1))

    if unsupported != [] do
      raise ArgumentError, "unsupported indexer options: #{inspect(unsupported)}"
    end

    :ok
  end
end
