# Setup

This sets up the backend with **no vaults**. When it is done, Claude can
connect and the timers run, with nothing to sync yet. Then add vaults one at a
time with [`vaults.md`](vaults.md), whether they are new or already exist.

Order matters: TLS must work before mobile devices can sync.

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
# Only if you will push history to GitHub (section 10): the GitHub CLI.
# https://github.com/cli/cli/blob/trunk/docs/install_linux.md

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

Leave `VAULTS` empty. `add-vault.sh` and `remove-vault.sh` manage it.

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

CouchDB's LiveSync settings come from `couchdb/local.d/10-livesync.ini`,
which is loaded at startup. Each vault's database is created later by
`add-vault.sh`, which also runs the upstream provisioner for it.

## 6. Bridge config

```bash
sudo ./scripts/gen-bridge-config.sh    # writes bridge/config.json with no vaults
```

Do not start the bridge yet; the first `add-vault.sh` does that. Generating the
file now matters anyway: if `bridge/config.json` is missing when anything
starts the bridge, Docker silently creates a *directory* in its place and the
bridge fails with a confusing parse error.

Never run `docker compose down --volumes`: it destroys the bridge's
`localStorage` and forces a complete re-scan.

## 7. Google OAuth and the MCP server

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

## 8. Google Drive backup

The default off-server copy. Configure the rclone remote named in
`RCLONE_REMOTE`:

```bash
sudo rclone config     # choose "drive"; use the headless flow and paste the
                       # token from a browser on your computer
sudo rclone lsd gdrive:
```

Run it with `sudo`: the backup timer runs as root and uses root's rclone config.

## 9. Timers

```bash
sudo cp systemd/* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemd-analyze verify /etc/systemd/system/vault-*.service
sudo systemctl enable --now vault-git.timer vault-backup.timer vault-staleness.timer
systemctl list-timers 'vault-*'
```

With no vaults yet, each run logs "No vaults configured" and succeeds. Vaults
you add later are picked up automatically.

`vault-git.timer` keeps local history for every vault in `/srv/git/<vault>.git`.
That needs no setup and gives a 15-minute undo for bad edits.

## 10. Optional: push history to GitHub

Off by default; the Drive backup is the off-server copy. To also push each
vault's history to its own private GitHub repo:

1. Install the GitHub CLI (section 2) and log in **as root**, because the timer
   runs as root:
   ```bash
   sudo gh auth login
   ```
   Your GitHub account, token and its permissions are yours to manage; the
   scripts only use the login. The token needs to create repos and push to them.
2. Set `GIT_PUSH=github` in `.env`. Set `GIT_REMOTE_OWNER` only to put the repos
   under an organization; by default they go to the account `gh` is logged in as.
3. For each vault you already have, run `sudo ./scripts/add-vault.sh <name>`
   once more. It creates the private repo (or reuses an existing one) and pushes
   the history. New vaults get their repo when you add them.

If the login expires, pushes log a warning and local history carries on.

## 11. Verify, then add your first vault

See the verification checklist in [`runbook.md`](runbook.md), then add vaults
with [`vaults.md`](vaults.md).
