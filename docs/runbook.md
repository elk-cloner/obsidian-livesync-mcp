# Runbook

## Verification checklist

Run after setup, and again after any upgrade. Checks 2 to 9 need at least one
vault ([`vaults.md`](vaults.md)); with none yet, skip them.

| # | Check | Command / action | Expected |
|---|---|---|---|
| 1 | CouchDB up | `curl -fsS -u "$COUCHDB_USER:$COUCHDB_PASSWORD" https://couch.$DOMAIN/_up` | `{"status":"ok"...}` |
| 2 | Databases exist | `curl -fsS -u "$COUCHDB_USER:$COUCHDB_PASSWORD" https://couch.$DOMAIN/_all_dbs` | one per vault |
| 3 | Device → device | new note on one device | appears on another |
| 4 | Device → mirror | new note on iPhone | appears in `/srv/vaults/<vault>` within seconds |
| 5 | Mirror → device | `echo '# x' > /srv/vaults/<vault>/x.md` | appears in Obsidian |
| 6 | Git history | `git --git-dir=/srv/git/<vault>.git log --oneline` | timed commits |
| 7 | Git push (only with `GIT_PUSH=github`) | GitHub repo page | commits present |
| 8 | Restore | `git --git-dir=… --work-tree=… checkout <sha> -- path/note.md` | note comes back |
| 9 | Backup | `rclone check /srv/vaults/<vault> $RCLONE_REMOTE:$RCLONE_BACKUP_PATH/<vault>` | no differences |
| 10 | MCP 401 | `curl -i https://mcp.$DOMAIN/mcp` | `401` + `www-authenticate` with `resource_metadata` |
| 11 | MCP metadata | `curl -s https://mcp.$DOMAIN/.well-known/oauth-protected-resource/mcp` | `resource` equals `https://mcp.$DOMAIN/mcp` exactly |
| 12 | Connector | add in claude.ai, authorize with Google | tools appear |
| 13 | MCP read/write | from the phone, ask Claude to read a note, write one, search | the new note reaches your other devices |
| 14 | Access control | authorize with a different Google account | tool calls rejected |
| 15 | Restart | `docker compose restart` then repeat 4, 5, 13 | works with **no** re-authorization |
| 16 | Sandbox | `python mcp/test_vaults.py` | 30 passed |

Check 15 is the one that catches a misconfigured `JWT_SIGNING_KEY` or a
non-persistent OAuth client store — the failure mode is a connector that
breaks silently days later.

## Decisions worth remembering

**`.obsidian` is not synced.** Plugins, themes and hotkeys are configured per
device. This avoids the `workspace.json` churn that causes constant conflicts,
and keeps iOS out of trouble. The cost: a new device needs its plugins set up
by hand. To reverse this, enable Hidden File Sync on every device *and* add
`.obsidian/**` to `includeInternal` in the bridge config, excluding
`workspace*.json`.

**Local history always, GitHub optional.** Every vault gets git history on the
server for a 15-minute undo, with no setup. Pushing it to GitHub is off by
default because the Drive backup already gives an off-server copy. Turn it on
with `GIT_PUSH=github` (see [`setup.md`](setup.md) section 10).

**With GitHub push on, notes reach GitHub unencrypted.** The pushed history is
a browsable, restorable archive; the trade-off is that GitHub (private repos)
can read the notes. CouchDB and the Drive backup are not affected: CouchDB holds
E2EE ciphertext, and the Drive copy is plain but in your own Drive.

**`trash_note` is server-side only.** `.trash` is hidden, so it never
replicates to devices. A trashed note leaves every device but stays on the
server and in git history. Empty it by hand.

## Secrets, and what losing each one costs

| Secret | Lives in | If lost | If leaked |
|---|---|---|---|
| `LIVESYNC_PASSPHRASE` | every device, `bridge/config.json` | **vaults unrecoverable** | CouchDB contents readable |
| `COUCHDB_PASSWORD` | `.env`, Setup URIs | rotate via CouchDB admin | server writable |
| `JWT_SIGNING_KEY` | `.env` | connector needs re-auth | tokens forgeable |
| `OAUTH_STORAGE_ENCRYPTION_KEY` | `.env` | client store unreadable → re-auth | stored tokens readable |
| Google client secret | `.env` | regenerate in Console | OAuth flow impersonable |
| GitHub CLI login (if `GIT_PUSH=github`) | root's `gh auth login` | log in again | whatever that token can reach |

Keep `LIVESYNC_PASSPHRASE` in a password manager. `chmod 600 .env` and
`bridge/config.json`; `gen-bridge-config.sh` sets the latter for you.

### Rotating the E2EE passphrase

Expensive — it re-encrypts everything. Rough shape: stop the bridge, change
the passphrase on one device and let it rewrite the remote database, update
`LIVESYNC_PASSPHRASE` in `.env`, regenerate the bridge config, re-onboard every
other device from a fresh Setup URI. Read the upstream docs first; do not
improvise.

## Failure modes

### The mirror goes stale

The quiet one. If the bridge dies, devices keep syncing through CouchDB and
nothing looks broken — but git history, the backup and Claude's view all
freeze. `vault-staleness.timer` runs hourly to catch it:

```bash
./scripts/bridge-staleness-check.sh
systemctl status vault-staleness.service
docker compose logs --tail=100 bridge
docker compose restart bridge
```

### Claude says "Couldn't reach the MCP server"

```bash
docker compose logs --tail=100 mcp
curl -i https://mcp.$DOMAIN/mcp                               # want 401, not 502
curl -s https://mcp.$DOMAIN/.well-known/oauth-protected-resource/mcp
```

Anthropic connects from `160.79.104.0/21`, **including** the OAuth discovery
calls. A firewall or fail2ban rule that blocks that range breaks the connector
with no visible error. Check:

```bash
ufw status; fail2ban-client status 2>/dev/null
```

If discovery is the problem, the signature is: the MCP server logs the first
request, and nothing reaches the OAuth endpoints at all.

### "Authorization with the MCP server failed"

Usually the Google redirect URI. It must be exactly
`https://mcp.<domain>/auth/callback`. Also confirm your address is still a
test user (Google Auth Platform → Audience), and that it matches `ALLOWED_EMAIL`.

### Conflicts

LiveSync surfaces conflicts in Obsidian rather than silently picking a side.
Resolve in the plugin's conflict view. To reduce them, read a note before
overwriting it — `write_note` without `overwrite=true` refuses to clobber an
existing file, which is the guard rail.

### A bad write reached every device

```bash
cd /srv/vaults/<vault>
git --git-dir=/srv/git/<vault>.git --work-tree=. log --oneline -- path/note.md
git --git-dir=/srv/git/<vault>.git --work-tree=. checkout <sha> -- path/note.md
```

The bridge picks the restored file up and pushes it out.

### CouchDB 413, or stalled fast-fetch

`request_body max_size` in the Caddyfile, and `flush_interval -1` on the
reverse proxy. Both are already set; check them if you have edited the file.

## Routine maintenance

```bash
# Upgrade the stack (pinned tags -- edit compose.yaml / bridge/Dockerfile first)
docker compose pull && docker compose up -d
docker compose build --no-cache bridge && docker compose up -d bridge

# Compact CouchDB after heavy editing
curl -X POST -u "$COUCHDB_USER:$COUCHDB_PASSWORD" \
  -H 'Content-Type: application/json' \
  "https://couch.$DOMAIN/<vault>/_compact"

# Garbage-collect a history repo
git --git-dir=/srv/git/<vault>.git gc --aggressive --prune=now
```

### Adding or removing a vault

```bash
sudo ./scripts/add-vault.sh <vault>          # run, onboard first device, run again
sudo ./scripts/remove-vault.sh <vault>       # archive; add --purge to delete the DB
```

Details in [`vaults.md`](vaults.md).

Never `docker compose down --volumes` — it wipes the bridge's scan state and
the stored OAuth client.
