FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Built from the repo root (see compose.yaml and /.dockerignore), so paths
# below are relative to it.

# Dependencies first so edits to the server don't invalidate the wheel cache.
# Keep these pins in step with pyproject.toml.
COPY backend/mcp/pyproject.toml ./
RUN pip install --no-cache-dir \
      "fastmcp==4.1.0" \
      "py-key-value-aio[disk]==0.4.6" \
      "cryptography==50.0.2" \
      "pyyaml==6.0.3"

COPY backend/mcp/server.py backend/mcp/vaults.py ./
# The one lint implementation, shared with the vault-lint skill.
COPY skills/vault-lint/scripts/lint.py ./vault_lint.py

# /srv/vaults is bind-mounted from the host and owned by the bridge's uid 1993.
# Run as that uid so notes Claude writes are indistinguishable from the
# bridge's own, and the bridge can replace them without permission trouble.
RUN groupadd -g 1993 vault && useradd -u 1993 -g 1993 -M -d /app vault \
 && mkdir -p /data/oauth-clients && chown -R 1993:1993 /data
USER 1993:1993

EXPOSE 8000
CMD ["python", "server.py"]
