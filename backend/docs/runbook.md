# Runbook

Run `sudo ./scripts/doctor.sh` first. It does most of the automatic checks in
one run, and changes nothing. Then do the manual checks below.

## Health check: `doctor.sh`

`doctor.sh` prints one line for each check: ✅ ok, ⚠️ warning or ❌ fail. A
line with a problem also gives a hint and the document to read. The script
exits with 1 if a check fails. It exits with 0 if all checks pass, also with
warnings.

It needs `sudo`, because `.env` is mode 600 and root owns it. Also, the
docker, systemd and rclone checks look at the daemon, units and rclone
configuration of root. With no vaults, the script skips the checks for each
vault. That is a normal state.

| Area | What `doctor.sh` checks |
|---|---|
| `.env` | Mode 600, and all necessary keys have a value (not `example.com`). |
| Containers | couchdb, caddy and mcp run. The bridge runs if `VAULTS` has a vault, and does not run if not. CouchDB is healthy. |
| CouchDB over TLS | `https://couch.<domain>/_up` answers. Each vault has a database. |
| Bridge | `bridge/config.json` exists, is a file, and agrees with `VAULTS`. The bridge log has no `error` or `EACCES` in the last 15 minutes. |
| Folders | `VAULT_ROOT` and each vault folder exist, and uid 1993 owns them. |
| MCP server | `/mcp` gives 401 with `resource_metadata`. The protected resource metadata names `https://mcp.<domain>/mcp`. The authorization server metadata has S256 and a registration endpoint. |
| Timers | The three timers are enabled and active. The result of the last run of each service. |
| History | Each vault has a history repository with a commit. A warning if the last commit is older than one hour. |
| Backup | The rclone remote of `RCLONE_REMOTE` exists. |
| Disk | Free space for `VAULT_ROOT`: fail below 500 MB, warning below 2 GB. |

## Verification checklist

Do this after setup, and again after each upgrade. Checks 2 to 9 need one
vault or more ([`vaults.md`](vaults.md)). If you have no vault, skip them.

The **doctor** column shows the checks that `doctor.sh` does for you. **yes**
is a full check and **part** is a partial check. An empty cell is a manual
check.

| # | Check | Command / action | Expected | doctor |
|---|---|---|---|---|
| 1 | CouchDB up | `curl -fsS -u "$COUCHDB_USER:$COUCHDB_PASSWORD" https://couch.$DOMAIN/_up` | `{"status":"ok"...}` | yes |
| 2 | Databases exist | `curl -fsS -u "$COUCHDB_USER:$COUCHDB_PASSWORD" https://couch.$DOMAIN/_all_dbs` | one for each vault | yes |
| 3 | Device → device | Make a new note on one device. | It comes into view on a different device. | |
| 4 | Device → mirror | Make a new note on the iPhone. | It comes into `/srv/vaults/<vault>` in a few seconds. | |
| 5 | Mirror → device | `echo '# x' > /srv/vaults/<vault>/x.md` | It comes into view in Obsidian. | |
| 6 | Git history | `git --git-dir=/srv/git/<vault>.git log --oneline` | commits at regular times | part (last commit only) |
| 7 | Git push (only with `GIT_PUSH=github`) | Open the page of the GitHub repository. | The commits are there. | |
| 8 | Restore | `git --git-dir=… --work-tree=… checkout <sha> -- path/note.md` | The note comes back. | |
| 9 | Backup | `rclone check /srv/vaults/<vault> $RCLONE_REMOTE:$RCLONE_BACKUP_PATH/<vault>` | no differences | part (remote exists) |
| 10 | MCP 401 | `curl -i https://mcp.$DOMAIN/mcp` | `401` and `www-authenticate` with `resource_metadata` | yes |
| 11 | MCP metadata | `curl -s https://mcp.$DOMAIN/.well-known/oauth-protected-resource/mcp` | `resource` is exactly `https://mcp.$DOMAIN/mcp` | yes |
| 12 | Connector | Add it in claude.ai and authorize with Google. | The tools come into view. | |
| 13 | MCP read/write | From the phone, ask Claude to read a note, write one, and search. | The new note comes to your other devices. | |
| 14 | Access control | Authorize with a different Google account. | The server refuses the tool calls. | |
| 15 | Restart | `docker compose restart`, then do 4, 5 and 13 again. | They work with **no** new authorization. | |
| 16 | Sandbox | `python mcp/test_vaults.py` | 0 failed | |
| 17 | Lint | `python mcp/test_lint.py` (needs PyYAML) | 0 failed | |
| 18 | Skills | `python3 ../skills/tools/build.py check` | `ok` | |

Check 15 finds a bad `JWT_SIGNING_KEY` or an OAuth client store that does not
persist. Without this check, the connector stops some days later and shows no
error.

## Decisions to remember

**`.obsidian` does not sync.** You configure plugins, themes and hotkeys on
each device.
This prevents the changes to `workspace.json` that cause
conflicts all the time, and keeps iOS out of trouble. The cost: you must
set up the plugins of a new device by hand. To change this decision, enable
Hidden File Sync on all devices. *Also* add `.obsidian/**` to
`includeInternal` in the bridge configuration, but exclude `workspace*.json`.

**Local history always, GitHub optional.** Each vault gets git history on the
server, with no setup. It gives a 15-minute undo. The push to GitHub is off by
default, because the Drive backup is already a copy outside the server. To
turn it on, set `GIT_PUSH=github` ([`setup.md`](setup.md), section 10).

**With the GitHub push on, the notes go to GitHub without encryption.** The
pushed history is an archive that you can browse and restore from. The cost is
that GitHub (private repositories) can read the notes. CouchDB and the Drive backup
do not change: CouchDB holds E2EE ciphertext. The Drive copy is plain text,
but it is in your own Drive.

**`trash_note` works only on the server.** `.trash` is a hidden folder, so it does not
replicate to devices. A note in the trash goes from all devices, but stays on
the server and in git history. Empty the trash by hand.

## Secrets, and the cost of a loss

| Secret | Where it is | If you lose it | If someone else gets it |
|---|---|---|---|
| `LIVESYNC_PASSPHRASE` | each device, `bridge/config.json` | **You cannot recover the vaults.** | They can read the CouchDB content. |
| `COUCHDB_PASSWORD` | `.env`, Setup URIs | Change it as CouchDB admin. | They can write to the server. |
| `JWT_SIGNING_KEY` | `.env` | You must authorize the connector again. | They can make false tokens. |
| `OAUTH_STORAGE_ENCRYPTION_KEY` | `.env` | The server cannot read the client store, so you must authorize again. | They can read the stored tokens. |
| Google client secret | `.env` | Make a new one in the Console. | They can act as your OAuth flow. |
| GitHub CLI login (if `GIT_PUSH=github`) | the `gh auth login` of root | Log in again. | They can get to all that the token can get to. |

Keep `LIVESYNC_PASSPHRASE` in a password manager. Set mode 600
(`chmod 600 .env`) on `.env` and `bridge/config.json`. `gen-bridge-config.sh`
does this for `bridge/config.json`.

### Change the E2EE passphrase

This change is expensive: it encrypts everything again. Read the upstream
documentation first. Do not improvise. The general procedure:

1. Stop the bridge.
2. Change the passphrase on one device. Let that device write the remote
   database again.
3. Change `LIVESYNC_PASSPHRASE` in `.env`.
4. Write the bridge configuration again (`sudo ./scripts/gen-bridge-config.sh`).
5. Connect all other devices again from a new Setup URI.

## Failure modes

### The mirror goes stale

This failure is quiet. If the bridge stops, devices continue to sync through
CouchDB, and nothing looks broken. But git history, the backup and the view of
Claude all stop. `vault-staleness.timer` runs each hour to find this failure.
`doctor.sh` also shows the last staleness result and the errors in the bridge
log.

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

`/mcp` must give 401, not 502.

Anthropic connects from `160.79.104.0/21`, **also** for the OAuth discovery
calls. If a firewall or fail2ban rule blocks that range, the connector stops
and shows no error. Check the rules:

```bash
ufw status; fail2ban-client status 2>/dev/null
```

If discovery is the problem, you see this: the MCP server logs the first
request, and no request comes to the OAuth endpoints.

### "Authorization with the MCP server failed"

The usual cause is the Google redirect URI. It must be exactly
`https://mcp.<domain>/auth/callback`. Also do these checks:

- If the app is in Testing, your address must still be a test user (Google
  Auth Platform → Audience).
- Your address must be the same as `ALLOWED_EMAIL`.

### Conflicts

LiveSync shows conflicts in Obsidian. It does not select a side without a
message. Resolve them in the conflict view of the plugin. To get fewer
conflicts, read a note before you overwrite it. `write_note` without
`overwrite=true` refuses to overwrite an existing file. That is the safety
rail.

### A bad write went to all devices

```bash
cd /srv/vaults/<vault>
git --git-dir=/srv/git/<vault>.git --work-tree=. log --oneline -- path/note.md
git --git-dir=/srv/git/<vault>.git --work-tree=. checkout <sha> -- path/note.md
```

The bridge sees the restored file and pushes it out.

### CouchDB 413, or fast-fetch stops

Look at `request_body max_size` in the Caddyfile, and at `flush_interval -1`
on the reverse proxy. The Caddyfile has the two settings already. If you
edited the file, check them.

### `doctor.sh` shows a failure

Each failed line gives the command that repairs it. These are the usual
lines:

| Line | Do this |
|---|---|
| `.env: mode …` | `sudo chmod 600 .env` |
| `.env: not set: …` | Run `sudo ./scripts/bootstrap.sh` ([`setup.md`](setup.md)). |
| `container … not running` | `docker compose up -d <service>`, then `docker compose logs --tail=100 <service>` |
| `bridge config: … is a directory` | `sudo rmdir bridge/config.json && sudo ./scripts/gen-bridge-config.sh` |
| `bridge config: has …, VAULTS has …` | `sudo ./scripts/gen-bridge-config.sh && docker compose restart bridge` |
| `folders: … is not owned by uid 1993` | `sudo chown -R 1993:1993 <folder>` |
| `timer …: not enabled` | `sudo ./scripts/install-timers.sh` |
| `timer …: last run ended with …` | `journalctl -u <timer>.service -n 50` |
| `rclone: no remote …` | `sudo rclone config` ([`setup.md`](setup.md), section 8) |

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

| Task | When |
|---|---|
| Upgrade the stack | The image tags have fixed versions. Edit `compose.yaml` or `bridge/Dockerfile` first. |
| Compact CouchDB | After many edits. |
| Clean a history repository | When it gets large. |

After an upgrade, run `sudo ./scripts/doctor.sh` and the verification
checklist.

### Add or remove a vault

```bash
sudo ./scripts/add-vault.sh <vault>          # onboard the first device while it waits
sudo ./scripts/remove-vault.sh <vault>       # archive; add --purge to delete the DB
```

[`vaults.md`](vaults.md) gives the details.

> **Warning:** Do not run `docker compose down --volumes`. It deletes the scan
> state of the bridge and the stored OAuth client.
