# DataplaneEx

This project is an Elixir implementation of Bluesky's dataplane.

It currently only supports inserting posts and follows and getting the timeline for a user.

You must set the following environment variables according to your setup.

* `BSKY_DATAPLANE_PORT`
* `BSKY_RELAY_WEBSOCKET`

To start your Phoenix server:

* Run `MIX_ENV=prod mix setup` to install and setup dependencies
* Start Phoenix endpoint with `MIX_ENV=prod mix phx.server` or inside IEx with `MIX_ENV=prod iex -S mix phx.server`

## Loading users and follows

You can load users and follows from CSV files.

Prepare the users CSV with a header row and one user DID per row. The parser
expects these columns:

```csv
user_did,indexedAt,trustedVerifier
did:plc:alice,2026-01-01T00:00:00Z,false
did:plc:bob,2026-01-01T00:00:00Z,false
```

Prepare the follows CSV with a header row. The parser reads the actor DID from
the third column and the subject DID from the fourth column:

```csv
uri,cid,actor_did,subject_did
at://did:plc:bob/app.bsky.graph.follow/1,bafyre...,did:plc:bob,did:plc:alice
```

Load users before follows, because follows reference existing users.

Start with IEx:

```sh
MIX_ENV=prod iex -S mix phx.server
```

Then run:

```elixir
alias DataplaneEx.Indexer

Indexer.bulk_users_from_file("/path/to/users.csv")
Indexer.bulk_follows_from_file("/path/to/follows.csv")
```

To delete all loaded data:

```elixir
Indexer.vacuum()
```
