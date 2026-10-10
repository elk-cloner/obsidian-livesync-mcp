# Migrating vaults off Google Drive

The one rule: **never point LiveSync at a directory Google Drive is still
syncing.** Two sync engines writing the same files produce conflict copies
faster than either can resolve them. Breaking the Drive link comes first,
always.

Do one vault at a time, smallest first as a rehearsal.

## Per vault

### 1. Quiesce

- Quit Obsidian on every device.
- Let Drive finish syncing on the computer that holds the vault — wait for the "up to date" state, not
  just a quiet icon.
- Note the file count you expect to end with:
  ```bash
  find "<drive-folder>/<vault>" -name '*.md' | wc -l
  ```

### 2. Break the Drive link

Copy the vault **out** of the Drive folder:

```bash
cp -a "<drive-folder>/<vault>" ~/Vaults/<vault>
```

Copy, don't move — the Drive folder stays as the rollback. Do not delete it
until a week of clean sync has passed.

### 3. Upload through LiveSync

Open `~/Vaults/<vault>` in Obsidian as a vault, then follow
[`onboarding.md`](onboarding.md) for the first device. Let the full upload
finish.

### 4. Verify against the mirror

Once the bridge is running:

```bash
# Counts should match what you noted in step 1.
find ~/Vaults/<vault> -name '*.md' | wc -l
find /srv/vaults/<vault> -name '*.md' | wc -l

# Spot-check content, not just counts.
md5sum ~/Vaults/<vault>/some/note.md
ssh vps "md5sum /srv/vaults/<vault>/some/note.md"
```

A count mismatch is usually hidden files or an in-progress sync. Investigate
before onboarding more devices — a second device will faithfully replicate
whatever is wrong.

### 5. Onboard remaining devices

From a fresh Setup URI generated on the first device. Let each one pull down; none of
them should upload.

### 6. Repoint anything that read the Drive copy

The nightly rclone backup writes to `ObsidianBackup/` on Drive, which is a
**new** location — it must never target the old vault folders. Check:

```bash
grep RCLONE_BACKUP_PATH .env
```

## Rollback

Within the first week, before deleting anything from Drive:

1. Disable the LiveSync plugin on every device.
2. Reopen the original vault folder inside Drive.
3. Delete the CouchDB database (`curl -X DELETE -u … https://couch.$DOMAIN/<vault>`)
   and the `/srv/vaults/<vault>` directory.

Nothing is lost, because the Drive copy was never touched.

## After all vaults are migrated

- If Claude reached the vaults through its Google Drive connector, switch it
  to the MCP connector. The Drive folder is no longer the live vault.
- The Drive copy under `ObsidianBackup/` is **output only**. Editing it changes
  nothing and will be overwritten by the next nightly sync.
