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

# Deno keeps localStorage (the bridge's sync state) under
# /deno-dir/location_data; the compose file mounts a named volume over it so
# the state survives. The directory must exist in the image: Docker gives a
# fresh volume the owner of the directory it is mounted on, and without it the
# volume is root-owned and the bridge fails with "Permission denied".
ENV DENO_DIR=/deno-dir
RUN mkdir -p /deno-dir/location_data && (deno install --allow-scripts || deno install)

# The base image already ships a `deno` user with uid/gid 1993 (creating it
# again fails the build). Run as it so /srv/vaults ownership lines up.
RUN chown -R 1993:1993 /app /deno-dir
USER 1993:1993

CMD ["deno", "task", "run"]
