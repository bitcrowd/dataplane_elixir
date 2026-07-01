import Config

if System.get_env("PHX_SERVER") do
  config :dataplane_ex, DataplaneExWeb.Endpoint, server: true
end

config :dataplane_ex, DataplaneExWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("BSKY_DATAPLANE_PORT", "2585"))]

if config_env() == :prod do
  bsky_relay_websocket =
    System.get_env("BSKY_RELAY_WEBSOCKET") ||
      raise """
      environment variable BSKY_RELAY_WEBSOCKET is missing.
      For example: wss://bsky.network
      """

  config :dataplane_ex, bsky_relay_websocket: bsky_relay_websocket

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :dataplane_ex, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  {:ok, bind_ip} =
    System.get_env("BSKY_DATAPLANE_IP", "127.0.0.1")
    |> String.to_charlist()
    |> :inet.parse_address()

  config :dataplane_ex, DataplaneExWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: bind_ip],
    secret_key_base: secret_key_base
end
