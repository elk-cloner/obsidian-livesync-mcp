# Architecture

<img src="../../docs/blueprints/01-system.svg" alt="Sheet 1 of 3, system overview: devices sync encrypted notes through Caddy to CouchDB; the bridge copies them to the mirror /srv/vaults/&lt;vault&gt;; the MCP server reads and writes the mirror for Claude; timers make the history, the backup and the staleness check" width="100%">

Devices and Claude come in through Caddy. All other parts connect to
`/srv/vaults`:

- The bridge keeps the mirror and CouchDB the same.
- Claude edits the mirror through the MCP server.
- Three timers copy the mirror out for the history, the backup and the
  health check.

On the sheet, a solid two-way arrow is live sync. A dashed one-way arrow is a
scheduled job. The GitHub push is optional, and it is off by default.

The backend runs with no vaults. `scripts/add-vault.sh` and
`scripts/remove-vault.sh` add and remove vaults one at a time
([`vaults.md`](vaults.md)). The older drawing of the same system is
[`architecture.svg`](architecture.svg).

## Components

Each part below has three lines. **In** is what it receives. **Out** is what
it sends. **Files** are the files that control it.

### Obsidian apps and the LiveSync plugin

You read and write notes here, on each device.

- **In:** changes from your other devices and from Claude. The plugin pulls
  them from CouchDB.
- **Out:** your edits. The device encrypts them with the LiveSync passphrase
  and pushes them to `couch.<domain>`.
- **Files:** [`onboarding.md`](onboarding.md), [`migration.md`](migration.md)

### Claude connector

The connector lets Claude on web, iPhone and iPad work with the vaults.

- **In:** tool results, for example note text, search results and write
  confirmations.
- **Out:** tool calls to `https://mcp.<domain>/mcp`, after one Google sign-in.

### Caddy (container)

Caddy is the only part that is open to the internet. It gets TLS
certificates from Let's Encrypt and routes two subdomains.

- **In:** HTTPS on ports 80 and 443.
- **Out:** `couch.*` → CouchDB :5984 and `mcp.*` → MCP :8000. Both routes
  have no buffer, so streams work.
- **Files:** [`caddy/Caddyfile`](../caddy/Caddyfile)

### CouchDB (container)

CouchDB connects all devices. It has one database for each vault. The
database holds encrypted note chunks, and CouchDB cannot read them. CouchDB
is its own HTTP server. LiveSync talks to it directly with the CouchDB
replication protocol. There is no app server between them.

- **In:** replication from devices (through Caddy) and from the bridge.
- **Out:** the same changes, replicated to all other peers.
- **Files:** [`couchdb/local.d/10-livesync.ini`](../couchdb/local.d/10-livesync.ini),
  [`scripts/couchdb-provision.sh`](../scripts/couchdb-provision.sh). CouchDB
  has no port on the host.

### livesync-bridge (container)

The bridge changes the encrypted CouchDB data into plain files. It also
changes file edits back into CouchDB data. Each vault gets one database peer
and one folder peer. The bridge runs on Deno.

- **In:** CouchDB changes, and the file changes that it sees in
  `/srv/vaults`. At a restart, it also scans for changes that it did not see.
- **Out:** decrypted `.md` files in the mirror, and encrypted edits to CouchDB.
- **Files:** [`bridge/`](../bridge/),
  [`scripts/gen-bridge-config.sh`](../scripts/gen-bridge-config.sh). The
  bridge needs `LIVESYNC_PASSPHRASE`.

### `/srv/vaults/<vault>/` (host folder)

This folder is the mirror: the plain-file copy of each vault. `/srv/vaults`
is the default. To move it, set `VAULT_ROOT` in `.env`. Each file that a part
writes here goes to all devices. All parts after the bridge read from here.

- **In:** writes from the bridge and from the MCP server.
- **Out:** reads by the MCP server, git, rclone and the staleness check.
- `add-vault.sh` makes one folder for each vault. `remove-vault.sh` moves a
  removed vault to `/srv/vaults-removed/`, where Claude cannot see it.
- uid 1993 owns the folder. The bridge and the MCP server both run as uid
  1993. `.obsidian` does not sync.

### MCP server (container)

The MCP server gives Claude ten tools for the vaults:

| Tool | What it does |
|---|---|
| `list_vaults` | Lists the vaults. |
| `list_notes` | Lists the notes in a vault. |
| `read_note` | Reads one note. |
| `note_info` | Gives the data about one note. |
| `search_notes` | Searches the notes. |
| `write_note` | Writes a note. |
| `append_note` | Adds text to the end of a note. |
| `trash_note` | Moves a note to `.trash`. |
| `vault_now` | Gives the UTC date and time that all notes use. |
| `lint_vault` | Does the structural lint, and writes `lint-report.md` into the vault. |

- **In:** tool calls from Claude, with a token. The token must carry the
  allowed email.
- **Out:** reads and atomic writes in `/srv/vaults`, locked inside each vault.
  The server cannot get to `.git`, `.obsidian` and `.trash`. `trash_note`
  moves a note. It does not delete it.
- **Files:** [`mcp/server.py`](../mcp/server.py), [`mcp/vaults.py`](../mcp/vaults.py),
  [`mcp/test_vaults.py`](../mcp/test_vaults.py). The lint code is
  [`lint.py`](../../skills/vault-lint/scripts/lint.py) of the vault-lint
  skill. The image build copies it into the image.

### Google OAuth (external)

Google OAuth proves who calls the MCP server. claude.ai connectors accept
only OAuth, so the MCP server uses Google for the sign-in.

- **In:** your Google sign-in when you set up the connector.
- **Out:** a token with your email. The server refuses all emails other than
  `ALLOWED_EMAIL`.
- `JWT_SIGNING_KEY` and the encrypted client-store volume must stay the same
  after a restart. If you lose one of them, you must authorize the connector
  again.

### vault-git → GitHub (timer, every 15 min)

This timer keeps the full version history of each note on the server. It
gives a 15-minute undo for bad edits.

- **In:** the current state of each vault folder.
- **Out:** a commit in `/srv/git/<vault>.git`, outside the synced folder.
  With `GIT_PUSH=github` (optional), it also pushes to one private GitHub
  repository for each vault. It uses the `gh auth login` of root.
- **Files:** [`scripts/vault-git-commit.sh`](../scripts/vault-git-commit.sh),
  `systemd/vault-git.*`

### vault-backup → Google Drive (timer, nightly 03:30)

This timer makes a copy outside the server. The copy is output only: the next
run overwrites edits that you make on Drive.

- **In:** `/srv/vaults`, without `.obsidian` and `.trash`. If the mirror has
  no markdown, the script stops and copies nothing.
- **Out:** `gdrive:ObsidianBackup`. The script keeps each replaced file in a
  dated `-replaced` folder.
- **Files:** [`scripts/vault-backup.sh`](../scripts/vault-backup.sh),
  `systemd/vault-backup.*`

### Staleness check (timer, hourly)

This timer finds a bridge that stopped. Without the bridge, devices continue
to sync through CouchDB. Thus nothing looks wrong, but git, the backup and
Claude get old data and show no error.

- **In:** the age of the files in each vault folder. After 24 h, a vault is
  stale.
- **Out:** exit 0 for fresh, 1 for stale, 2 for missing. If the check fails,
  the systemd journal shows the unit as failed.
- **Files:** [`scripts/bridge-staleness-check.sh`](../scripts/bridge-staleness-check.sh),
  `systemd/vault-staleness.*`

## Two flows, step by step

**You edit a note on your iPhone**

1. LiveSync encrypts the change and sends it to `couch.<domain>`.
2. Caddy sends it to CouchDB.
3. CouchDB replicates it to your other devices and to the bridge.
4. The bridge decrypts it and writes the `.md` file into `/srv/vaults`.
5. In 15 minutes or less, the timer commits it to local history.
6. If the GitHub push is on, the timer also pushes it to GitHub.
7. That night, the backup copies it to Drive.

**Claude writes a note**

1. Claude calls `write_note` on `mcp.<domain>/mcp`.
2. Caddy sends the call to the MCP server.
3. The MCP server checks the email in the token.
4. The server writes the file into `/srv/vaults`, inside the sandbox of the vault.
5. The bridge sees the new file, encrypts it and pushes it to CouchDB.
6. Your devices pull it down in a few seconds.

If you edit a note on a device while Claude writes the same note, CouchDB
keeps the two versions as a conflict. LiveSync then asks you to resolve it.

## Secrets on the sync path

| Secret | Who has it | If you lose it | If someone else gets it |
|---|---|---|---|
| `COUCHDB_PASSWORD` | devices, bridge, `.env` | Set a new one as admin. | They can sync with the server, but they see only encrypted data. |
| `LIVESYNC_PASSPHRASE` | devices, bridge | **You cannot recover the vaults.** | They can read the stored data. |
| `LIVESYNC_OBFUSCATE_PASSPHRASE` (the default is the E2EE passphrase) | devices, bridge | It must be the same on all peers, or sync stops. | They can read the note names. |
| Setup URI passphrase | you, for one onboarding | Make a new URI. | They can read only that one URI. |
