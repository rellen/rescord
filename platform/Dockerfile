# The image of Rescord (ADR 0044): the release of `mix release` on Debian
# trixie, with the Erlang runtime inside it.
#
#   docker build -t rescord platform
#
# Behind a proxy that inspects TLS, give its certificate as a secret, and
# the build trusts it while it fetches the dependencies:
#
#   docker build --secret id=extra_ca,src=proxy-ca.pem -t rescord platform

ARG ELIXIR_VERSION=1.20.5
ARG OTP_VERSION=29.1.3
ARG DEBIAN_VERSION=trixie-20261123-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS build

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# A certificate of a proxy, when the build has one. It joins the
# certificates of the system, which git, Hex and esbuild read.
RUN --mount=type=secret,id=extra_ca,required=false \
  if [ -s /run/secrets/extra_ca ]; then \
    cp /run/secrets/extra_ca /usr/local/share/ca-certificates/extra_ca.crt \
    && update-ca-certificates; \
  fi

# vix takes its NIF and a libvips for the web formats from its release on
# GitHub, with checksums that its package holds, and the release carries
# both in the priv of vix: the image and the tarball need no libvips of
# the system (ADR 0055).
ENV MIX_ENV=prod \
  HEX_CACERTS_PATH=/etc/ssl/certs/ca-certificates.crt \
  VIX_COMPILATION_MODE=PRECOMPILED_NIF_AND_LIBVIPS

WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mkdir config
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets
RUN mix compile
RUN mix esbuild.install --if-missing && mix assets.deploy

COPY config/runtime.exs config/
COPY rel rel
RUN mix release

# The tarball of the release (ADR 0044), for a server with no Docker:
#   docker build --target tarball --output type=local,dest=dist platform
# scripts/release-tarball.sh builds it on Debian bookworm, for glibc 2.36.
FROM build AS tarball-build
ARG TARGETARCH
RUN mkdir /dist \
  && tar -C _build/prod/rel -czf "/dist/rescord-linux-${TARGETARCH}.tar.gz" rescord

FROM scratch AS tarball
COPY --from=tarball-build /dist/ /

FROM ${RUNNER_IMAGE} AS image

# The base image has a date; the upgrade takes the security fixes of Debian
# since then, at each build (ADR 0048).
RUN apt-get update \
  && apt-get upgrade -y --no-install-recommends \
  && apt-get install -y --no-install-recommends \
    libstdc++6 openssl libncurses6 locales ca-certificates curl \
  && rm -rf /var/lib/apt/lists/* \
  && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 \
  LANGUAGE=en_US:en \
  LC_ALL=en_US.UTF-8 \
  MIX_ENV=prod \
  PORT=4000 \
  RESCORD_FILES_DIR=/var/lib/rescord/files \
  RELEASE_DISTRIBUTION=none

WORKDIR /app
RUN useradd --system --home /app --shell /usr/sbin/nologin rescord \
  && mkdir -p /var/lib/rescord/files \
  && chown -R rescord:rescord /app /var/lib/rescord

COPY --from=build --chown=rescord:rescord /app/_build/prod/rel/rescord ./

USER rescord
VOLUME /var/lib/rescord/files
EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s \
  CMD curl -fsS "http://localhost:${PORT}/health" || exit 1

# Each start runs the migrations that have not run, then the server.
CMD ["/bin/sh", "-c", "/app/bin/migrate && exec /app/bin/server"]
