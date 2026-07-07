ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=28.4.3
ARG DEBIAN_VERSION=bookworm-20260623-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y \
    && apt-get install -y build-essential git ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib

RUN mix compile

COPY config/runtime.exs config/

RUN mix release

## Runner Image
FROM ${RUNNER_IMAGE}

RUN apt-get update -y \
    && apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/dataplane_ex ./

ENV PHX_SERVER="true" \
    BSKY_DATAPLANE_IP="0.0.0.0"

EXPOSE 2585

CMD ["bin/dataplane_ex", "start"]
