defmodule DataplaneEx.Progress do
  @moduledoc """
  Lightweight terminal progress reporting for bulk operations.

  Provides three mechanisms:

    - **Stream-based** (`each_with_progress/4`) — for Elixir-side iteration,
      prints a `\\r`-overwriting line every ~1 second.
    - **COPY polling** (`monitor_copy/1` + `stop_monitor/1`) — spawns a task
      that polls `pg_stat_progress_copy` for server-side COPY operations.
    - **CREATE INDEX polling** (`monitor_create_index/1` + `stop_monitor/1`) —
      spawns a task that polls `pg_stat_progress_create_index` for index builds.
  """

  require Logger

  @print_interval_ms 1_000

  @doc """
  Count data lines in a CSV file (excludes the header row).

  Reads in 256 KB binary chunks and counts newline characters.
  """
  def count_lines(filepath) do
    filepath
    |> File.stream!(256 * 1024)
    |> Enum.reduce(0, fn chunk, acc ->
      acc + count_newlines(chunk)
    end)
    |> Kernel.-(1)
    |> max(0)
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

  @doc """
  Spawns a poller that queries `pg_stat_progress_copy` every second and
  prints COPY progress. Returns a reference to pass to `stop_monitor/1`.

  The poller uses a separate Repo connection from the pool.
  """
  def monitor_copy(label) do
    parent = self()
    started_at = System.monotonic_time(:millisecond)

    pid =
      spawn_link(fn ->
        copy_poll_loop(parent, label, started_at)
      end)

    pid
  end

  @doc "Stops the COPY monitor and prints the final summary line."
  def stop_monitor(pid) do
    send(pid, :stop)

    receive do
      {:progress_stopped, final_tuples, elapsed_ms} ->
        if final_tuples > 0 do
          rate = rate_string(final_tuples, elapsed_ms)

          Logger.info(
            "\r\e[2K#{format_number(final_tuples)} rows — #{rate} — #{format_duration(elapsed_ms)}\n"
          )
        end
    after
      2_000 -> :ok
    end
  end

  @doc """
  Spawns a poller that queries `pg_stat_progress_create_index` every second
  and prints index-build progress (phase, tuples, blocks). Returns a pid
  to pass to `stop_monitor/1`.
  """
  def monitor_create_index(label) do
    parent = self()
    started_at = System.monotonic_time(:millisecond)

    spawn_link(fn ->
      index_poll_loop(parent, label, started_at)
    end)
  end

  # ---------------------------------------------------------------------------
  # COPY poller internals
  # ---------------------------------------------------------------------------

  defp copy_poll_loop(parent, label, started_at) do
    receive do
      :stop ->
        now = System.monotonic_time(:millisecond)
        send(parent, {:progress_stopped, 0, now - started_at})
    after
      @print_interval_ms ->
        {tuples, bytes_pct} = query_copy_progress()
        now = System.monotonic_time(:millisecond)
        elapsed = now - started_at

        if tuples > 0 do
          rate = rate_string(tuples, elapsed)

          eta =
            if bytes_pct > 0.0 do
              remaining_ms = trunc(elapsed / bytes_pct * (1.0 - bytes_pct))
              " — ETA #{format_duration(remaining_ms)}"
            else
              ""
            end

          Logger.info(
            "\r\e[2K#{label}: #{format_number(tuples)} rows (#{Float.round(bytes_pct * 100, 1)}%) — #{rate}#{eta}"
          )
        end

        wait_or_stop(parent, label, started_at, tuples)
    end
  end

  defp wait_or_stop(parent, label, started_at, last_tuples) do
    receive do
      :stop ->
        Logger.info("\r\e[2K")
        now = System.monotonic_time(:millisecond)
        send(parent, {:progress_stopped, last_tuples, now - started_at})
    after
      0 -> copy_poll_loop(parent, label, started_at)
    end
  end

  defp query_copy_progress do
    try do
      result =
        DataplaneEx.Repo.query!(
          "SELECT tuples_processed, bytes_processed, bytes_total FROM pg_stat_progress_copy LIMIT 1",
          [],
          timeout: 5_000
        )

      case result.rows do
        [[tuples, bytes_done, bytes_total]] when bytes_total > 0 ->
          {tuples, bytes_done / bytes_total}

        [[tuples, _bytes_done, _bytes_total]] ->
          {tuples, 0.0}

        [] ->
          {0, 0.0}
      end
    rescue
      _ -> {0, 0.0}
    end
  end

  # ---------------------------------------------------------------------------
  # CREATE INDEX poller internals
  # ---------------------------------------------------------------------------

  defp index_poll_loop(parent, label, started_at) do
    receive do
      :stop ->
        now = System.monotonic_time(:millisecond)
        send(parent, {:progress_stopped, 0, now - started_at})
    after
      @print_interval_ms ->
        progress = query_index_progress()
        now = System.monotonic_time(:millisecond)
        elapsed = now - started_at

        print_index_progress(label, progress, elapsed)

        index_wait_or_stop(parent, label, started_at, progress)
    end
  end

  defp index_wait_or_stop(parent, label, started_at, last_progress) do
    receive do
      :stop ->
        Logger.info("\r\e[2K")
        now = System.monotonic_time(:millisecond)
        tuples = last_progress[:tuples_done] || 0
        send(parent, {:progress_stopped, tuples, now - started_at})
    after
      0 -> index_poll_loop(parent, label, started_at)
    end
  end

  defp print_index_progress(_label, nil, _elapsed), do: :ok

  defp print_index_progress(label, progress, elapsed) do
    phase = progress.phase
    tuples_done = progress.tuples_done
    tuples_total = progress.tuples_total
    blocks_done = progress.blocks_done
    blocks_total = progress.blocks_total

    pct_part =
      cond do
        tuples_total > 0 ->
          pct = Float.round(tuples_done / tuples_total * 100, 1)
          " #{format_number(tuples_done)}/#{format_number(tuples_total)} tuples (#{pct}%)"

        blocks_total > 0 ->
          pct = Float.round(blocks_done / blocks_total * 100, 1)
          " #{format_number(blocks_done)}/#{format_number(blocks_total)} blocks (#{pct}%)"

        tuples_done > 0 ->
          " #{format_number(tuples_done)} tuples"

        true ->
          ""
      end

    Logger.info("\r\e[2K#{label}: #{phase}#{pct_part} — #{format_duration(elapsed)}")
  end

  defp query_index_progress do
    result =
      DataplaneEx.Repo.query!(
        "SELECT phase, tuples_total, tuples_done, blocks_total, blocks_done FROM pg_stat_progress_create_index LIMIT 1",
        [],
        timeout: 5_000
      )

    case result.rows do
      [[phase, tuples_total, tuples_done, blocks_total, blocks_done]] ->
        %{
          phase: phase,
          tuples_total: tuples_total,
          tuples_done: tuples_done,
          blocks_total: blocks_total,
          blocks_done: blocks_done
        }

      [] ->
        nil
    end
  end

  # ---------------------------------------------------------------------------
  # Formatting helpers
  # ---------------------------------------------------------------------------

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
end
