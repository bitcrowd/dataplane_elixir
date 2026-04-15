Application.ensure_all_started(:dataplane_ex)

DataplaneEx.Repo.query!("TRUNCATE posts, follows, users RESTART IDENTITY CASCADE")

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(DataplaneEx.Repo, :manual)
Ecto.Adapters.SQL.Sandbox.mode(DataplaneEx.WriteRepo, :manual)
