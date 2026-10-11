# Backend: self-hosted Obsidian sync and Claude MCP access

The backend replaces Google Drive sync for more than one Obsidian vault. You
own all of it:

- Device sync through your own CouchDB.
- A plain-file mirror of each vault on the server.
- Git history with no limit.
- A nightly one-way backup to Google Drive.
- A custom MCP connector. Claude can read *and write* the vaults from all
  surfaces (web, iPhone, iPad).

The backend is one of three parts of this repository. The
[root README](../README.md) tells how the backend, the vault schema and the
skills fit together.

## Start here

To set up a new server, use the quick start: [`../docs/quickstart.md`](../docs/quickstart.md).
It runs `sudo ./scripts/bootstrap.sh`, then adds the first vault.

| To do this | Read |
|---|---|
| Set up the backend in one run | [`../docs/quickstart.md`](../docs/quickstart.md) |
| Do one setup step by hand, or repair one step | [`docs/setup.md`](docs/setup.md) |
| Add or remove a vault | [`docs/vaults.md`](docs/vaults.md) |
| Connect a device | [`docs/onboarding.md`](docs/onboarding.md) |
| Move notes out of Google Drive | [`docs/migration.md`](docs/migration.md) (read it first) |
| Check the health, find a fault | [`docs/runbook.md`](docs/runbook.md) |
| Learn what each part does | [`docs/architecture.md`](docs/architecture.md) |

<a href="docs/architecture.md"><img src="../docs/blueprints/01-system.svg" alt="System overview: devices sync through Caddy to CouchDB, the bridge copies notes to the mirror in /srv/vaults, the MCP server gives Claude access to the mirror, and timers make the history, the backup and the staleness check" width="100%"></a>

`VAULT_ROOT` (`/srv/vaults` by default) is the center of the backend. All
the other parts read it. The bridge and CouchDB send each write in it to all
devices. [`docs/architecture.md`](docs/architecture.md) gives the job, the
inputs and the outputs of each part.

## The two stages

1. **Backend.** Set up the backend one time, with no vaults.
   `sudo ./scripts/bootstrap.sh` does this. `sudo ./scripts/doctor.sh` checks
   the result at any time.
2. **Vaults.** Add the vaults one at a time with
   `sudo ./scripts/add-vault.sh <name>`. New vaults and existing vaults use
   the same steps.

To remove a vault, run `sudo ./scripts/remove-vault.sh <name>`.

**Backups:** each vault gets local git history (a 15-minute undo) and a
nightly copy on Google Drive. A push of the history to private GitHub
repositories is optional. Read [`docs/setup.md`](docs/setup.md), section 10.

## Layout

| Path | What it is |
|---|---|
| `compose.yaml` | CouchDB, livesync-bridge, the MCP server, Caddy |
| `.env.example` | All secrets and settings, with the host paths. Each one has a comment. |
| `caddy/Caddyfile` | TLS and the reverse proxy for the two subdomains |
| `couchdb/local.d/` | The CouchDB settings that LiveSync needs |
| `bridge/` | The image of the bridge and its peer configuration (generated) |
| `mcp/` | The MCP server: `server.py` (auth, tools) and `vaults.py` (path sandbox). Its image also holds `lint.py` of the vault-lint skill. |
| `scripts/` | `bootstrap.sh`, `doctor.sh`, `add-vault.sh` / `remove-vault.sh` / `seed-vault.sh`, `install-timers.sh`, and the scripts for provision, git history, backup and health |
| `systemd/` | Unit templates for the history, the backup and the staleness check |
| `docs/` | Architecture, setup, vaults, device onboarding, migration, runbook |

This repository holds configuration and code only. **Do not put vault
content in this repository.**

## Why OAuth and not an API key

Custom connectors in claude.ai accept only OAuth or no authentication. Static
bearer-token headers exist, but only some organizations can use them (beta).
A server with no authentication gives a writable vault to all persons who know
the URL.

Thus `mcp/server.py` uses the `GoogleProvider` of FastMCP. It gives
Claude an OAuth interface that agrees with DCR and CIMD. It signs you in with
one Google client that you register first. Then it lets only one email in.

## Tests

```bash
python mcp/test_vaults.py            # path-sandbox cases, no framework needed
python mcp/test_lint.py              # lint on the template and the examples (needs PyYAML)
./scripts/bridge-staleness-check.sh  # is the mirror still moving?
```

The sandbox tests are the most important tests. Each case tries to read or
write outside a vault.
