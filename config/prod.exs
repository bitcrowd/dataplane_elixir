import Config

config :dataplane_ex, DataplaneExWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

config :logger, level: :info
