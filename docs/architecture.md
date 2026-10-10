# Architecture

![Architecture blueprint](architecture.svg)

Devices and Claude both come in through Caddy. Everything else hangs off
`/srv/vaults`: the bridge keeps it in step with CouchDB, Claude edits it
through the MCP server, and three timers copy it out for history, backup and
health checks.

Solid two-way arrows are live sync. Dashed one-way arrows are scheduled jobs.
The GitHub push is optional and off by default.

The backend runs with no vaults; `scripts/add-vault.sh` and
`scripts/remove-vault.sh` add and remove them one at a time
(see [`vaults.md`](vaults.md)).

## Components

### Obsidian apps + LiveSync plugin
Where you read and write notes on each device.

- **In:** changes from your other devices and from Claude, pulled from CouchDB.
- **Out:** your edits, encrypted on the device with the LiveSync passphrase,
  pushed to `couch.<domain>`.
- **Files:** [`onboarding.md`](onboarding.md), [`migration.md`](migration.md)

### Claude connector
Lets Claude on web, iPhone and iPad work with the vaults.

- **In:** tool results such as note text, search hits and write confirmations.
- **Out:** tool calls to `https://mcp.<domain>/mcp`, after a one-time Google
  sign-in.

### Caddy (container)
The only thing open to the internet. Gets TLS certificates from Let's Encrypt
and routes two subdomains.

- **In:** HTTPS on ports 80 and 443.
- **Out:** `couch.*` → CouchDB :5984 and `mcp.*` → MCP :8000, both unbuffered
  so streaming works.
- **Files:** [`caddy/Caddyfile`](../caddy/Caddyfile)

### CouchDB (container)
The meeting point for every device. One database per vault, holding encrypted
note chunks it cannot read. CouchDB is its own HTTP server: LiveSync talks to
it directly with CouchDB's replication protocol, with no app server in between.

- **In:** replication from devices (via Caddy) and from the bridge.
- **Out:** the same changes, replicated to every other peer.
- **Files:** [`couchdb/local.d/10-livesync.ini`](../couchdb/local.d/10-livesync.ini),
  [`scripts/couchdb-provision.sh`](../scripts/couchdb-provision.sh). No host
  port is exposed.

### livesync-bridge (container)
Turns the encrypted CouchDB data into plain files, and file edits back into
CouchDB. Each vault gets one database peer and one folder peer. Runs on Deno.

- **In:** CouchDB changes, and file changes it watches in `/srv/vaults`
  (plus a scan on restart for anything it missed).
- **Out:** decrypted `.md` files in the mirror; re-encrypted edits to CouchDB.
- **Files:** [`bridge/`](../bridge/),
  [`scripts/gen-bridge-config.sh`](../scripts/gen-bridge-config.sh). Needs
  `LIVESYNC_PASSPHRASE`.

### `/srv/vaults/<vault>/` (host folder)
The plain-file copy of every vault. Anything written here reaches every
device; everything downstream reads from here.

- **In:** writes from the bridge and from the MCP server.
- **Out:** read by the MCP server, git, rclone and the staleness check.
- One folder per vault, created by `add-vault.sh`. `remove-vault.sh` moves a
  removed vault to `/srv/vaults-removed/`, out of Claude's sight.
- Owned by uid 1993, which the bridge and the MCP server both run as.
  `.obsidian` is not synced.

### MCP server (container)
Gives Claude eight tools over the vaults: `list_vaults`, `list_notes`,
`read_note`, `note_info`, `search_notes`, `write_note`, `append_note`,
`trash_note`.

- **In:** tool calls from Claude, with a token that must carry the allowed
  email.
- **Out:** reads and atomic writes in `/srv/vaults`, locked inside each vault.
  `.git`, `.obsidian` and `.trash` are unreachable; trashing moves a note,
  never deletes it.
- **Files:** [`mcp/server.py`](../mcp/server.py), [`mcp/vaults.py`](../mcp/vaults.py),
  [`mcp/test_vaults.py`](../mcp/test_vaults.py)

### Google OAuth (external)
Proves who is calling. claude.ai connectors only accept OAuth, so the MCP
server uses Google as the sign-in.

- **In:** your Google sign-in during connector setup.
- **Out:** a token with your email. Any email other than `ALLOWED_EMAIL` is
  rejected.
- `JWT_SIGNING_KEY` and the encrypted client-store volume must survive
  restarts; lose either and the connector has to be re-authorized.

### vault-git → GitHub (timer, every 15 min)
Full version history of every note, kept on the server; a 15-minute undo for
bad edits.

- **In:** the current state of each vault folder.
- **Out:** a commit in `/srv/git/<vault>.git` (kept outside the synced folder).
  Optionally (`GIT_PUSH=github`) pushed to a private GitHub repo per vault,
  using root's `gh auth login`.
- **Files:** [`scripts/vault-git-commit.sh`](../scripts/vault-git-commit.sh),
  `systemd/vault-git.*`

### vault-backup → Google Drive (timer, nightly 03:30)
An off-site copy. Output only: edits made on Drive get overwritten.

- **In:** `/srv/vaults`, minus `.obsidian` and `.trash`. Refuses to run if the
  mirror has no markdown.
- **Out:** `gdrive:ObsidianBackup`; replaced files are parked in a dated
  `-replaced` folder.
- **Files:** [`scripts/vault-backup.sh`](../scripts/vault-backup.sh),
  `systemd/vault-backup.*`

### Staleness check (timer, hourly)
Catches a dead bridge. Devices keep syncing through CouchDB without it, so
nothing looks wrong while git, backup and Claude silently go stale.

- **In:** file ages in each vault folder (stale after 24 h).
- **Out:** exit 0 fresh, 1 stale, 2 missing. A failure marks the unit failed in
  the systemd journal.
- **Files:** [`scripts/bridge-staleness-check.sh`](../scripts/bridge-staleness-check.sh),
  `systemd/vault-staleness.*`

## Two flows, traced

**You edit a note on your iPhone**

1. LiveSync encrypts the change and sends it to `couch.<domain>`.
2. Caddy passes it to CouchDB.
3. CouchDB replicates it to your other devices and to the bridge.
4. The bridge decrypts it and writes the `.md` file into `/srv/vaults`.
5. Within 15 minutes it is committed to local history (and pushed to GitHub,
   if enabled); that night it is copied to Drive.

**Claude writes a note**

1. Claude calls `write_note` on `mcp.<domain>/mcp`.
2. Caddy passes it to the MCP server, which checks the token's email.
3. The server writes the file into `/srv/vaults`, inside the vault's sandbox.
4. The bridge sees the new file, encrypts it and pushes it to CouchDB.
5. Your devices pull it down within seconds.

If you edit a note on a device while Claude writes the same note, CouchDB keeps
both versions as a conflict and LiveSync asks you to resolve it.

## Secrets on the sync path

| Secret | Who holds it | If you lose it | If it leaks |
|---|---|---|---|
| `COUCHDB_PASSWORD` | devices, bridge, `.env` | reset it as admin | someone can sync with the server, but sees only encrypted data |
| `LIVESYNC_PASSPHRASE` | devices, bridge | **vaults are unrecoverable** | the stored data becomes readable |
| `LIVESYNC_OBFUSCATE_PASSPHRASE` | devices, bridge | must match to sync | note names become readable |
| Setup URI `uri_passphrase` | you, for one onboarding | generate a new URI | only that one URI is exposed |
