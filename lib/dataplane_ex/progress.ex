defmodule DataplaneEx.Progress do
  @moduledoc """
  Terminal progress reporting for bulk operations.
  """

  require Logger

  @print_interval_ms 1_000

  @doc """
  Count data lines in a CSV file (excludes the header row).

  Reads in 256 KB binary chunks and counts newline characters.
  """
  def count_lines(filepath) do
    lines =
      filepath
      |> File.stream!(256 * 1024)
      |> Enum.reduce(0, fn chunk, acc ->
        acc + count_newlines(chunk)
      end)

    if lines > 0 do
      lines - 1
    else
      0
    end
  end

  defp count_newlines(<<>>), do: 0

  defp count_newlines(binary) do
    for <<byte <- binary>>, byte == ?\n, reduce: 0 do
      acc -> acc + 1
    end
  end

  @doc """
  Iterates `enumerable`, calling `fun` on each element while printing
  progress every ~1 second. Returns `:ok`.

  `total` is the expected number of items (from `count_lines/1`).
  `label` is a short string printed as the operation name.

  ## Options

    - `:step` — count increment per element (default `1`). Use this when
      iterating batches but tracking individual row counts.
  """
  def each_with_progress(enumerable, total, label, fun, opts \\ []) do
    step = Keyword.get(opts, :step, 1)
    started_at = System.monotonic_time(:millisecond)
    last_print = started_at
    count = 0

    {final_count, _} =
      Enum.reduce(enumerable, {count, last_print}, fn element, {n, lp} ->
        fun.(element)
        n = n + step
        now = System.monotonic_time(:millisecond)

        if now - lp >= @print_interval_ms do
          print_progress(label, n, total, started_at, now)
          {n, now}
        else
          {n, lp}
        end
      end)

    finish(label, final_count, started_at)
    :ok
  end

  defp print_progress(label, count, 0, started_at, now) do
    elapsed = now - started_at
    rate = rate_string(count, elapsed)
    Logger.info("\r\e[2K#{label}: #{format_number(count)} rows — #{rate}")
  end

  defp print_progress(label, count, total, started_at, now) do
    elapsed = now - started_at
    pct = Float.round(count / total * 100, 1)
    rate = rate_string(count, elapsed)

    eta =
      if count > 0 do
        remaining = trunc((total - count) / count * elapsed)
        " — ETA #{format_duration(remaining)}"
      else
        ""
      end

    Logger.info(
      "\r\e[2K#{label}: #{format_number(count)} / #{format_number(total)} (#{pct}%) — #{rate}#{eta}"
    )
  end

  defp finish(label, count, started_at) do
    elapsed = System.monotonic_time(:millisecond) - started_at
    rate = rate_string(count, elapsed)

    Logger.info(
      "\r\e[2K#{label}: #{format_number(count)} rows — #{rate} — #{format_duration(elapsed)}\n"
    )
  end

  defp rate_string(_count, elapsed) when elapsed <= 0, do: "—"

  defp rate_string(count, elapsed) do
    per_sec = count / elapsed * 1000

    cond do
      per_sec >= 1_000_000 -> "#{Float.round(per_sec / 1_000_000, 1)}M rows/s"
      per_sec >= 1_000 -> "#{Float.round(per_sec / 1_000, 1)}K rows/s"
      true -> "#{trunc(per_sec)} rows/s"
    end
  end

  defp format_number(n) when n >= 1_000_000_000 do
    "#{Float.round(n / 1_000_000_000, 2)}B"
  end

  defp format_number(n) when n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 1)}M"
  end

  defp format_number(n) when n >= 1_000 do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/.{3}/, "\\0,")
    |> String.replace(~r/,$/, "")
    |> String.reverse()
  end

  defp format_number(n), do: Integer.to_string(n)

  defp format_duration(ms) when ms < 1_000, do: "<1s"
  defp format_duration(ms) when ms < 60_000, do: "#{div(ms, 1_000)}s"

  defp format_duration(ms) do
    minutes = div(ms, 60_000)
    seconds = div(rem(ms, 60_000), 1_000)
    "#{minutes}m #{seconds}s"
  end

  def total_from_file(path) do
    DataplaneEx.CSV.read_meta(path)[:total] || count_lines(path)
  end

  def total_from_source(source, opts) when is_binary(source) do
    Keyword.get_lazy(opts, :total, fn -> line_count(source) end)
  end

  def total_from_source(_source, opts) do
    Keyword.get(opts, :total, 0)
  end

  def line_count(contents) do
    lines =
      contents
      |> String.split("\n", trim: true)
      |> length()

    if lines > 0 do
      lines - 1
    else
      0
    end
  end
end
