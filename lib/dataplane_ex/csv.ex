defmodule DataplaneEx.CSV do
  @moduledoc """
  CSV parsers for the simulator's data files.

  Each CSV may have a companion `.meta` file (same base name, `.meta` extension)
  containing key-value metadata such as `total: 40000000`.  Use `read_meta/1`
  to load it and `write_meta/2` to create one alongside a CSV.
  """

  alias NimbleCSV.RFC4180, as: Parser

  @type source :: String.t() | Enumerable.t()

  @doc """
  Reads the `.meta` companion file for `csv_path`.
  """
  @spec read_meta(String.t()) :: %{optional(atom()) => integer()}
  def read_meta(csv_path) do
    meta_path = Path.rootname(csv_path) <> ".meta"

    case File.read(meta_path) do
      {:ok, contents} -> parse_meta(contents)
      {:error, _} -> %{}
    end
  end

  @doc """
  Writes a `.meta` companion file next to `csv_path`.
  """
  @spec write_meta(String.t(), map()) :: :ok
  def write_meta(csv_path, meta) when is_map(meta) do
    meta_path = Path.rootname(csv_path) <> ".meta"
    lines = Enum.map(meta, fn {k, v} -> "#{k}: #{v}\n" end)
    File.write!(meta_path, lines)
    :ok
  end

  defp parse_meta(contents) do
    contents
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] ->
          key = key |> String.trim() |> String.to_existing_atom()
          value = value |> String.trim() |> String.to_integer()

          Map.put(acc, key, value)

        _ ->
          acc
      end
    end)
  end

  @doc """
  Parses a user CSV into a stream of user IDs.
  """
  @spec parse_users(source()) :: Enumerable.t()
  def parse_users(source) do
    source
    |> parse()
    |> Stream.map(fn [user_did | _rest] -> user_did end)
  end

  @doc """
  Parses an edges CSV into a stream of tuples.
  """
  @spec parse_edges(source()) :: Enumerable.t()
  def parse_edges(source) do
    source
    |> parse()
    |> Stream.map(fn [_uri, _cid, actor_did, subject_did | _rest] ->
      {actor_did, subject_did}
    end)
  end

  @doc """
  Parses a posts CSV into a stream of `{offset_ms, user_id}` tuples.
  """
  @spec parse_posts(source()) :: Enumerable.t()
  def parse_posts(source) do
    source
    |> parse()
    |> Stream.map(fn [offset_ms, user_id | _rest] ->
      {String.to_integer(offset_ms), user_id}
    end)
  end

  defp parse(content) when is_binary(content) do
    content
    |> Parser.parse_string(skip_headers: true)
    |> reject_blank_rows()
  end

  defp parse(source) do
    source
    |> Parser.parse_stream(skip_headers: true)
    |> reject_blank_rows()
  end

  defp reject_blank_rows(rows) do
    Stream.reject(rows, &(&1 == [""]))
  end
end
