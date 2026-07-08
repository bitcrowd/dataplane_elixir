defmodule DataplaneEx.TmpFileFixtures do
  @moduledoc false

  def tmp_path(prefix, ext \\ ".csv") do
    Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}#{ext}")
  end

  def tmp_file(prefix, content, ext \\ ".csv") do
    path = tmp_path(prefix, ext)

    File.write!(path, content)
    ExUnit.Callbacks.on_exit(fn -> File.rm(path) end)

    path
  end

  def meta_path(path), do: Path.rootname(path) <> ".meta"

  def cleanup_meta(path) do
    ExUnit.Callbacks.on_exit(fn -> meta_path(path) |> File.rm() end)
  end
end
