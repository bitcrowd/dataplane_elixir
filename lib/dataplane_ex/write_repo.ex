defmodule DataplaneEx.WriteRepo do
  @moduledoc """
  Write-side Ecto repository for Postgres mutations.
  """

  use Ecto.Repo, otp_app: :dataplane_ex, adapter: Ecto.Adapters.Postgres
end
