# Setup

Order matters: TLS must work before mobile devices can sync, and CouchDB must
be provisioned before the bridge starts.

## 1. DNS

Two A records pointing at the VPS:

- `couch.<domain>` — CouchDB
- `mcp.<domain>` — the MCP server

CouchDB has to sit at the **root** of its own subdomain. Serving it under a
path breaks LiveSync with "404 Database not found" unless `/_session` is also
proxied and the path rewritten — not worth the trouble.

## 2. Host prerequisites

```bash
# Docker, Deno 2 (for the upstream provisioner), rclone, git
curl -fsSL https://get.docker.com | sh
curl -fsSL https://deno.land/install.sh | sh
apt-get install -y rclone git

git clone <this repo> /opt/obsidian-self-host
cd /opt/obsidian-self-host
```

The repo path is baked into the systemd units as `/opt/obsidian-self-host`.
Put it elsewhere and you must edit `systemd/*.service` to match.

## 3. Secrets

```bash
cp .env.example .env
chmod 600 .env

# Generate the ones that must be random:
openssl rand -base64 32                       # COUCHDB_PASSWORD
openssl rand -base64 48                       # JWT_SIGNING_KEY
python3 -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'
                                              # OAUTH_STORAGE_ENCRYPTION_KEY
```

Set `LIVESYNC_PASSPHRASE` to a strong passphrase of your own and **store it in
a password manager now**. It is the E2EE key: every device needs it, the bridge
needs it, and nothing can recover the vaults without it.

`VAULTS` is a space-separated list. Each name becomes a CouchDB database, a
directory under `/srv/vaults`, a git repo, and a bridge peer group — so use
only `[A-Za-z0-9._-]`.

## 4. Directories

```bash
# CouchDB chowns its config directory to uid/gid 5984 on first start.
sudo chown -R 5984:5984 couchdb/local.d

# The mirror. Both the bridge and the MCP server run as uid 1993, so it
# must be owned by that uid -- root-owned and mode 755 would leave both
# containers able to read but not write.
sudo install -d -m 755 -o 1993 -g 1993 /srv/vaults

# History repos, driven by root via systemd, deliberately outside the mirror.
sudo install -d -m 700 /srv/git
```

## 5. CouchDB behind TLS

```bash
docker compose up -d couchdb caddy
docker compose logs -f caddy          # watch the certificate get issued
curl -fsS https://couch.$DOMAIN/_up   # {"status":"ok", ...}
```

Then provision it. This delegates to the upstream provisioner so the settings
always match what the plugin expects, instead of a copy that drifts:

```bash
./scripts/couchdb-provision.sh
curl -fsS -u "$COUCHDB_USER:$COUCHDB_PASSWORD" https://couch.$DOMAIN/_all_dbs
```

`couchdb/local.d/10-livesync.ini` records the same settings for reference and
so a rebuilt server comes up correct before the provisioner runs.

## 6. Onboard the first device

Do this **before** starting the bridge, so the first full upload comes from a
device holding a known-good vault rather than from an empty server directory.
See [`onboarding.md`](onboarding.md), then [`migration.md`](migration.md) for
moving a vault off Google Drive.

## 7. The bridge

```bash
./scripts/gen-bridge-config.sh    # writes bridge/config.json, mode 600
docker compose up -d bridge
docker compose logs -f bridge
ls -la /srv/vaults/<vault>/       # plain markdown should appear
```

The first run scans both sides fully. If the mirror looks incomplete, restart
once with `--reset` (`docker compose run --rm bridge deno task run --reset`).

Never run `docker compose down --volumes`: it destroys the bridge's
`localStorage` and forces a complete re-scan.

## 8. Google OAuth for the MCP server

In [Google Cloud Console](https://console.cloud.google.com/apis/credentials):

1. **OAuth consent screen** — External, and add your own address as the only
   test user. Nobody else needs to reach this.
2. **Credentials → Create OAuth client ID** → Web application.
   - Authorized redirect URI: `https://mcp.<domain>/auth/callback`
     (exactly — this is FastMCP's default `redirect_path`)
3. Put the client ID and secret in `.env`.

Claude's own callback (`https://claude.ai/api/mcp/auth_callback`) is **not**
registered with Google. FastMCP's OAuth proxy terminates that leg itself.

```bash
docker compose up -d mcp

# Claude's first request looks like this:
curl -i https://mcp.$DOMAIN/mcp
# expect: 401 with
#   www-authenticate: Bearer ... resource_metadata="https://mcp.<domain>/.well-known/oauth-protected-resource/mcp"

curl -s https://mcp.$DOMAIN/.well-known/oauth-protected-resource/mcp | jq .
# "resource" must equal https://mcp.<domain>/mcp exactly

curl -s https://mcp.$DOMAIN/.well-known/oauth-authorization-server | jq \
  '{code_challenge_methods_supported, registration_endpoint,
    client_id_metadata_document_supported, token_endpoint_auth_methods_supported}'
# S256, a registration endpoint, and both CIMD markers
```

Then in claude.ai: **Customize → Connectors → + → Add custom connector**, URL
`https://mcp.<domain>/mcp`. Sign in with Google when prompted.

## 9. Timers

```bash
sudo cp systemd/* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemd-analyze verify /etc/systemd/system/vault-*.service
sudo systemctl enable --now vault-git.timer vault-backup.timer vault-staleness.timer
systemctl list-timers 'vault-*'
```

Before the git timer can push, create one **private** GitHub repo per vault
named exactly after the vault, and give the VPS a deploy key with write
access at `/root/.ssh/vault_deploy` (the path in `vault-git.service`).

For the backup, configure the rclone remote named in `RCLONE_REMOTE`:

```bash
rclone config          # choose "drive"; use the headless flow and paste the
                       # token from a browser on your computer
rclone lsd gdrive:
```

## 10. Verify end to end

See the verification checklist in [`runbook.md`](runbook.md).
