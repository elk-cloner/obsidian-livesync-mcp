# Adding and removing vaults

The backend runs with no vaults at all. Vaults are added one at a time, and
the steps are the same whether the notes are brand new or already exist.

## Add a vault

`add-vault.sh` is one command that you run twice. Between the two runs, the
first device uploads the vault.

```bash
sudo ./scripts/add-vault.sh <name>      # 1. creates the database
# ... connect the first device and let it upload ...
sudo ./scripts/add-vault.sh <name>      # 2. connects the vault to the server
```

Names may use letters, digits, `.`, `_` and `-`, and must not start with `.`.
The name becomes the CouchDB database, the folder `/srv/vaults/<name>`, the
history repo and, if GitHub push is on, the GitHub repo.

### 1. First run: the database

Creates the vault's CouchDB database and prints what to do next. Nothing else
changes yet: the vault is not in `VAULTS`, so the bridge and timers ignore it.

### 2. Connect the first device

On a desktop, follow [`onboarding.md`](onboarding.md) for the first device,
using a Setup URI for this database. The only difference between new and
existing notes is which folder you open in Obsidian:

- **New vault:** create an empty vault in Obsidian.
- **Existing notes:** open that vault's folder. If it lives in Google Drive,
  follow [`migration.md`](migration.md) first to copy it out of Drive.

Let the first upload finish completely.

The order matters: the first device writes the database's LiveSync settings,
and the bridge reads them when it connects.

### 3. Second run: connect it to the server

Run the same command again. Once the database holds the uploaded notes, it:

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

### 4. Other devices

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

If the database was kept, it still holds the notes, so one run connects the
vault straight away.

`add-vault.sh` refuses to re-add a vault while its files are still parked, so
the bridge never starts from an empty folder it thinks used to be full. To
start over from scratch instead, delete the parked folder first, and use
`--purge` when removing so the old database goes too.
