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
cd /opt/obsidian-self-host/backend
```

Any checkout path works, as long as it has no spaces. Every command in this
guide runs from `backend/`. The repo root also holds `vault/` (the schema that
`seed-vault.sh` copies into vaults) and `skills/` (the Claude skills).

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

The host paths (`VAULT_ROOT`, `GIT_ROOT`, `REMOVED_ROOT`) default to `/srv/...`.
Change them in `.env` if you want them elsewhere; compose and every script read
them from there. The commands below load `.env` so they follow your choice.

## 4. Directories

```bash
# CouchDB chowns its config directory to uid/gid 5984 on first start.
sudo chown -R 5984:5984 couchdb/local.d

set -a; . ./.env; set +a

# The mirror. Both the bridge and the MCP server run as uid 1993, so it
# must be owned by that uid -- root-owned and mode 755 would leave both
# containers able to read but not write. 1993 is fixed: the bridge's base
# image ships that user.
sudo install -d -m 755 -o 1993 -g 1993 "${VAULT_ROOT:-/srv/vaults}"

# History repos, driven by root via systemd, deliberately outside the mirror.
sudo install -d -m 700 "${GIT_ROOT:-/srv/git}"
```

## 5. CouchDB behind TLS

```bash
docker compose up -d couchdb caddy
docker compose logs -f caddy          # watch the certificate get issued
set -a; . ./.env; set +a              # load DOMAIN and the CouchDB login
curl -fsS -u "$COUCHDB_USER:$COUCHDB_PASSWORD" https://couch.$DOMAIN/_up
# {"status":"ok", ...}  (a 401 means it was asked without the login)
```

CouchDB's LiveSync settings come from `couchdb/local.d/10-livesync.ini`,
which is loaded at startup. Each vault's database is created later by
`add-vault.sh`, which also runs the upstream provisioner for it.

## 6. Bridge config

```bash
sudo ./scripts/gen-bridge-config.sh    # writes bridge/config.json with no vaults
```

Do not start the bridge yet; `add-vault.sh` starts it when it connects the
first vault. Generating the
file now matters anyway: if `bridge/config.json` is missing when anything
starts the bridge, Docker silently creates a *directory* in its place and the
bridge fails with a confusing parse error.

Never run `docker compose down --volumes`: it destroys the bridge's
`localStorage` and forces a complete re-scan.

## 7. Google OAuth and the MCP server

In [Google Cloud Console](https://console.cloud.google.com/auth/overview),
under **Google Auth Platform** (formerly "OAuth consent screen"):

1. **Overview → Get started.** Any app name and your email as support email;
   **Audience: External** ("Internal" exists only for Google Workspace
   organizations); your email as contact; accept the policy; **Create**.
2. **Audience → Test users → Add users:** your own address, the same one as
   `ALLOWED_EMAIL`. Nobody else needs to reach this. Leave the publishing
   status on **Testing**.
3. **Clients → Create client** → Web application.
   - Authorized redirect URI: `https://mcp.<domain>/auth/callback`
     (exactly — this is FastMCP's default `redirect_path`)
4. Put the client ID and secret in `.env`. Copy the secret right away; the
   Console may show it in full only once.

Branding, Data Access and Verification Center can stay as they are: the server
asks only for `openid` and `userinfo.email`, basic scopes that need no review.

In Testing mode Google expires sign-ins after 7 days. If the connector asks you
to reconnect about weekly, use **Audience → Publish app**. With only basic
scopes there is no review, and `ALLOWED_EMAIL` still rejects every other
account.

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
./scripts/install-timers.sh --dry-run   # optional: see the units it will write
sudo ./scripts/install-timers.sh
```

The units in `systemd/` are templates. The script fills in this checkout's
path, installs them, verifies them, and enables the three timers. Re-run it
after moving the checkout or pulling unit changes.

With no vaults yet, each run logs "No vaults configured" and succeeds. Vaults
you add later are picked up automatically.

`vault-git.timer` keeps local history for every vault in `$GIT_ROOT/<vault>.git`.
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
with [`vaults.md`](vaults.md). A new vault gets the knowledge vault schema with
`sudo ./scripts/seed-vault.sh <name>` once it is connected.

Then install the skills that work the vault: see
[`skills/README.md`](../../skills/README.md).
