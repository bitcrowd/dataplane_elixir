defmodule DataplaneEx.Indexer do
  @moduledoc """
  Dataplane indexer interface.
  """

  @callback bulk_users(source :: String.t() | Enumerable.t(), opts :: keyword()) ::
              :ok | {:error, term()}
  @callback bulk_follows(source :: String.t() | Enumerable.t(), opts :: keyword()) ::
              :ok | {:error, term()}
  @callback bulk_load_posts(source :: String.t() | Enumerable.t(), opts :: keyword()) ::
              :ok | {:error, term()}
  @callback vacuum() :: :ok
  @callback count_users() :: non_neg_integer()
  @callback count_follows() :: non_neg_integer()
  @type user_id :: String.t()

  @callback followers(user_id()) :: [user_id()]
  @callback following(user_id()) :: [user_id()]
  @callback create_post(%{user_id: user_id()}) :: :ok | {:error, term()}
  @callback toggle_follow(%{actor_id: user_id(), subject_id: user_id()}) ::
              :ok | {:error, term()}
  @callback posts_planned() :: non_neg_integer()
  @callback posts_created() :: non_neg_integer()

  @active_indexer_key :dataplane_ex_active_indexer

  @doc "Registers `module` as the active indexer."
  def register_active(module) do
    :persistent_term.put(@active_indexer_key, module)
  end

  @doc "Returns the currently registered indexer module, or `nil`."
  def active_indexer do
    :persistent_term.get(@active_indexer_key, nil)
  end

  def validate_options!(opts, supported) do
    unsupported = opts |> Keyword.keys() |> Enum.reject(&MapSet.member?(supported, &1))

    if unsupported != [] do
      raise ArgumentError, "unsupported indexer options: #{inspect(unsupported)}"
    end

    :ok
  end
end
