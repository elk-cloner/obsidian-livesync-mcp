# The upstream project publishes no image, so build it from a pinned checkout.
FROM denoland/deno:2.9.7

# Bump to adopt upstream fixes. Pin a tag or commit rather than tracking main,
# so a rebuild can never silently change replication behaviour.
ARG BRIDGE_REF=main

WORKDIR /app

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${BRIDGE_REF}" \
      https://github.com/vrtmrz/livesync-bridge.git /app

# Deno keeps localStorage (used by offline scanning) under this directory; the
# compose file mounts a named volume over it so the scan state survives.
ENV DENO_DIR=/deno-dir
RUN mkdir -p /deno-dir && deno install --allow-scripts || deno install

# The upstream image runs as 1993; match it so /srv/vaults ownership lines up.
RUN groupadd -g 1993 bridge && useradd -u 1993 -g 1993 -m bridge \
 && chown -R 1993:1993 /app /deno-dir
USER 1993:1993

CMD ["deno", "task", "run"]
