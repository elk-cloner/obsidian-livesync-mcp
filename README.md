# Self-hosted Obsidian sync + Claude MCP access

Replaces Google Drive sync for multiple Obsidian vaults with a stack you own:
device sync through your own CouchDB, a plain-file mirror on the server,
unlimited git history, a nightly one-way backup to Drive, and a custom MCP
connector that lets Claude read *and write* the vaults from any surface
(web, iPhone, iPad).

[![Architecture blueprint](docs/architecture.svg)](docs/architecture.md)

`/srv/vaults` is the hinge: everything downstream reads it, and writes into it
flow back out to every device via the bridge and CouchDB. Each component's job,
inputs and outputs are in [`docs/architecture.md`](docs/architecture.md).

## Layout

| Path | What it is |
|---|---|
| `compose.yaml` | CouchDB, livesync-bridge, MCP server, Caddy |
| `.env.example` | every secret and setting, documented |
| `caddy/Caddyfile` | TLS and reverse proxy for both subdomains |
| `couchdb/local.d/` | LiveSync's required CouchDB settings |
| `bridge/` | bridge image and peer config (generated) |
| `mcp/` | the MCP server: `server.py` (auth, tools), `vaults.py` (path sandbox) |
| `scripts/` | provisioning, git history, backup, health |
| `systemd/` | timers for history, backup and the staleness check |
| `docs/` | architecture, setup, device onboarding, migration, runbook |

Configuration and code only — **no vault content ever lives in this repo.**

## Setup

Full detail in [`docs/setup.md`](docs/setup.md). The short version:

```bash
git clone <this repo> /opt/obsidian-self-host && cd /opt/obsidian-self-host
cp .env.example .env && chmod 600 .env && "$EDITOR" .env   # fill everything in

sudo install -d -o 5984 -g 5984 couchdb/local.d
sudo install -d -m 755 -o 1993 -g 1993 /srv/vaults   # uid both containers run as
sudo install -d -m 700 /srv/git

docker compose up -d couchdb caddy
./scripts/couchdb-provision.sh        # needs Deno 2
./scripts/gen-bridge-config.sh
docker compose up -d                  # bridge + mcp

sudo cp systemd/* /etc/systemd/system/
sudo systemctl enable --now vault-git.timer vault-backup.timer vault-staleness.timer
```

Then onboard devices ([`docs/onboarding.md`](docs/onboarding.md)), move the
vaults off Drive ([`docs/migration.md`](docs/migration.md)), and add the
connector at `https://mcp.<domain>/mcp` in claude.ai.

## Why OAuth and not an API key

claude.ai custom connectors accept only OAuth or no authentication. Static
bearer-token headers exist but are beta-gated to specific organizations, and
an authless server would leave a writable vault open to anyone with the URL.
So `mcp/server.py` uses FastMCP's `GoogleProvider`, which presents a
DCR/CIMD-compliant OAuth interface to Claude while authenticating you against
one pre-registered Google client — then narrows access to a single email.

## Tests

```bash
python mcp/test_vaults.py            # 30 path-sandbox cases, no framework needed
./scripts/bridge-staleness-check.sh  # is the mirror still moving?
```

The sandbox tests are the ones that matter: every case is an attempt to read
or write outside a vault.
