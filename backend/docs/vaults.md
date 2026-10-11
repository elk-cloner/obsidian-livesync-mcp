# Adding and removing vaults

The backend runs with no vaults at all. Vaults are added one at a time, and
the steps are the same whether the notes are brand new or already exist.

## Add a vault

`add-vault.sh` does the whole job in one run. It creates the database, prints
a Setup URI, waits while you connect the first device, and connects the vault
to the server once that device has uploaded.

```bash
sudo ./scripts/add-vault.sh <name>      # 1-3. database, first device, connect
sudo ./scripts/seed-vault.sh <name>     # 4. new vault: puts the schema in
```

Names may use letters, digits, `.`, `_` and `-`, and must not start with `.`.
The name becomes the CouchDB database, the folder `/srv/vaults/<name>`, the
history repo and, if GitHub push is on, the GitHub repo.

### 1. The database and a Setup URI

`add-vault.sh` creates the vault's CouchDB database and prints a Setup URI
with its one-time passphrase, for the first device. Nothing else changes yet:
the vault is not in `VAULTS`, so the bridge and timers ignore it. Nothing it
prints needs to be kept ([`onboarding.md`](onboarding.md) explains why).

Then it waits, watching the database. Leave it running while you do step 2.

### 2. Connect the first device

On a desktop, follow [`onboarding.md`](onboarding.md) for the first device,
importing the Setup URI from step 1. Don't set LiveSync up by hand. The only difference between new and
existing notes is which folder you open in Obsidian:

- **New vault:** create an empty vault in Obsidian.
- **Existing notes:** open that vault's folder. If it lives in Google Drive,
  follow [`migration.md`](migration.md) first to copy it out of Drive.

Let the first upload finish completely.

The order matters: the first device writes the database's LiveSync settings,
and the bridge reads them when it connects. That is why `add-vault.sh` waits.

### 3. Connect it to the server

As soon as documents appear in the database, `add-vault.sh` shows the count
and waits for the upload to settle: no change for 30 seconds. Then, in the
same run, it:

1. creates the private GitHub repo, or reuses an existing one (only when
   `GIT_PUSH=github`; it tells you before creating anything);
2. adds the name to `VAULTS` in `.env`;
3. creates `/srv/vaults/<name>`, owned by the containers' uid 1993;
4. regenerates `bridge/config.json` and starts or restarts the bridge;
5. waits for the notes to appear in `/srv/vaults/<name>`;
6. makes the first history commit, and pushes it if GitHub push is on.

From then on Claude can see the vault, and the git, backup and staleness timers
include it. A brand-new empty vault makes the staleness check warn until it
has a note; that is expected.

### If the wait is interrupted

Ctrl+C while it waits is safe: only the database exists at that point. Run
the same command again to carry on. If the database is still empty, it prints
a fresh URI and waits again; if the first device has uploaded, it connects the
vault straight away. If no upload starts within an hour, it stops by itself
with the same advice.

For scripts, `--no-wait` keeps the older behaviour: it prints the URI and
exits. Run `sudo ./scripts/add-vault.sh <name>` again once the first upload
has finished, and that run connects the vault.

### 4. Seed the schema

A new vault starts empty. Put the knowledge vault schema into it:

```bash
sudo ./scripts/seed-vault.sh <name>
```

It copies `vault/template` from this repo into the vault folder: the root
`CLAUDE.md` (the schema), `README.md`, `log.md`, `_templates/` and `_bases/`.
The bridge pushes the files out and the first device receives them within
seconds. It refuses to run on a vault that already has a root `CLAUDE.md`, or
to overwrite any file, so it is safe to try on a vault that has notes.

When the schema in this repo changes, refresh a vault's copy:

```bash
sudo ./scripts/seed-vault.sh <name> --upgrade
```

That replaces only the root `CLAUDE.md`, `_templates/` and `_bases/`. Areas,
`log.md`, `README.md` and the current-area marker are never touched. It commits
history before and after, so the previous files can be restored from git.

See [`vault/README.md`](../../vault/README.md) for the schema itself and the
per-device Obsidian settings.

### 5. Other devices

Onboard them from a fresh Setup URI generated on the first device
([`onboarding.md`](onboarding.md)). They should download, not upload.

Running `add-vault.sh` on a vault that is already added only re-checks every
step. That is also how existing vaults get their GitHub repos after you turn
on GitHub push.

## Remove a vault

```bash
sudo ./scripts/remove-vault.sh <name>            # archive, delete nothing
sudo ./scripts/remove-vault.sh <name> --purge    # also delete the database
```

It asks you to type the vault name, then:

| Step | What happens |
|---|---|
| Final snapshot | commits the vault's current state to history (and pushes if GitHub push is on) |
| Disconnect | removes it from `VAULTS`, regenerates the bridge config, restarts the bridge (or stops it if no vaults are left) |
| Park the files | moves `/srv/vaults/<name>` to `/srv/vaults-removed/<name>-<timestamp>/`, so Claude no longer sees it |
| Keep | `/srv/git/<name>.git` and the GitHub repo, untouched |
| CouchDB database | kept, unless `--purge` (asks again; cannot be undone) |

The bridge is disconnected **before** the folder moves. A bridge still watching
the folder would read the move as "every note deleted" and push that to every
device.

Then, by hand:

- On each device, disable Self-hosted LiveSync for that vault, or delete the
  local vault. A device that keeps syncing would recreate it in CouchDB.
- Nothing to do for Google Drive: the next nightly backup moves the vault's
  copy into the dated `ObsidianBackup-replaced/` folder.

### Bringing a removed vault back

Move the parked folder back, then add it as usual:

```bash
sudo mv /srv/vaults-removed/<name>-<timestamp> /srv/vaults/<name>
sudo ./scripts/add-vault.sh <name>
```

If the database was kept, it still holds the notes, so `add-vault.sh` prints
no Setup URI: it checks for 30 seconds that nothing is still uploading, then
connects the vault.

`add-vault.sh` refuses to re-add a vault while its files are still parked, so
the bridge never starts from an empty folder it thinks used to be full. To
start over from scratch instead, delete the parked folder first, and use
`--purge` when removing so the old database goes too.
