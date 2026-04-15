defmodule DataplaneEx.WriteRepo do
  use Ecto.Repo, otp_app: :dataplane_ex, adapter: Ecto.Adapters.Postgres
end
