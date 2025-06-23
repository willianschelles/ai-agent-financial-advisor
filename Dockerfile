# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=ubuntu
# https://hub.docker.com/_/ubuntu?tab=tags
#
ARG ELIXIR_VERSION=1.14.5
ARG OTP_VERSION=26.0.2
ARG DEBIAN_VERSION=bullseye-20230612-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as builder

# Install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Prepare build directory
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# Set build ENV
ENV MIX_ENV="prod"

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy config files
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy assets
COPY assets assets
COPY priv priv

# Compile assets
RUN mix assets.deploy

# Copy application code
COPY lib lib

# Compile application
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

# Build the release
COPY rel rel
RUN mix release

# Create app directory in runner
FROM ${RUNNER_IMAGE} AS runner

# Install runtime dependencies
RUN apt-get update -y && \
  apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# Set runner ENV
ENV MIX_ENV="prod"
ENV PHX_SERVER="true"

# Copy the release from the builder
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/ai_agent ./

# Create a script to run migrations
COPY --from=builder --chown=nobody:root /app/rel/overlays ./

# Create the runtime directories
RUN mkdir -p /app/tmp

USER nobody

CMD ["/app/bin/server"]
