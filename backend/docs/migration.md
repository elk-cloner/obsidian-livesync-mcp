# Move vaults off Google Drive

Read this page before you add a vault whose notes sync through Google Drive
now. It tells how to get the notes out of Drive safely. Then you add the vault
in the usual way, with [`vaults.md`](vaults.md).

> **Warning:** Do not connect LiveSync to a folder that Google Drive still
> syncs. Two sync engines that write the same files make conflict copies
> faster than either engine can resolve them. Always disconnect Drive first.

Do one vault at a time. Do the smallest vault first, as a test.

## For each vault

### 1. Stop all changes

1. Quit Obsidian on all devices.
2. Let Drive finish its sync on the computer that holds the vault. Wait for
   the "up to date" state. A quiet icon is not sufficient.
3. Write down the number of files that you expect at the end:
   ```bash
   find "<drive-folder>/<vault>" -name '*.md' | wc -l
   ```

### 2. Disconnect Drive

Copy the vault **out** of the Drive folder:

```bash
cp -a "<drive-folder>/<vault>" ~/Vaults/<vault>
```

Copy the folder. Do not move it. The Drive folder stays as the rollback copy.
Do not delete it until the sync works with no problems for one week.

### 3. Add the vault

1. Run `sudo ./scripts/add-vault.sh <vault>` ([`vaults.md`](vaults.md)).
2. While it waits, open `~/Vaults/<vault>` in Obsidian as a vault. This is
   the first device.
3. Let the full upload finish.

When the upload is quiet, `add-vault.sh` connects the vault. The bridge
copies it to the mirror on the server.

### 4. Compare with the mirror

When `add-vault.sh` shows that the vault is connected, do these checks:

```bash
# Counts should match what you noted in step 1.
find ~/Vaults/<vault> -name '*.md' | wc -l
find /srv/vaults/<vault> -name '*.md' | wc -l

# Spot-check content, not just counts.
md5sum ~/Vaults/<vault>/some/note.md
ssh vps "md5sum /srv/vaults/<vault>/some/note.md"
```

The two counts must agree with the number from step 1. Also compare the
content of some notes, not only the counts.

If the counts do not agree, the cause is usually hidden files or a sync that
did not finish. Find the cause before you connect more devices. A second
device copies each problem exactly.

### 5. Connect the other devices

Use a new Setup URI from the first device. Let each device download the
vault. No other device may upload.

### 6. Change all that read the Drive copy

The nightly rclone backup writes to `ObsidianBackup/` on Drive. This is a
**new** location. It must not write to the old vault folders. Check it:

```bash
grep RCLONE_BACKUP_PATH .env
```

## Rollback

In the first week, before you delete anything from Drive:

1. Disable the LiveSync plugin on all devices.
2. Open the original vault folder in Drive again.
3. Remove the vault from the server: `sudo ./scripts/remove-vault.sh <vault> --purge`.
4. Delete the parked copy in `/srv/vaults-removed/`.

You lose nothing, because nothing changed the Drive copy.

## After you move all vaults

- If Claude used its Google Drive connector for the vaults, change to the MCP
  connector. The Drive folder is not the live vault now.
- The Drive copy in `ObsidianBackup/` is **output only**. Edits to it change
  nothing. The next nightly sync overwrites them.
