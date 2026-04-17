# DataplaneEx

This project is an Elixir implementation of Bluesky's dataplane.

It currently only supports inserting posts and follows and getting the timeline for a user.

You must set the following environment variables according to your setup.

* `BSKY_DB_POSTGRES_URL`
* `BSKY_DATAPLANE_PORT`
* `BSKY_RELAY_WEBSOCKET`

To start your Phoenix server:

* Run `MIX_ENV=prod mix setup` to install and setup dependencies
* Start Phoenix endpoint with `MIX_ENV=prod mix phx.server` or inside IEx with `MIX_ENV=prod iex -S mix phx.server`

