#!/usr/bin/env bash
# Nightly one-way backup of the vault mirror to Google Drive.
#
# The Drive copy is OUTPUT ONLY. Editing it changes nothing and will be
# overwritten on the next run; edit notes in Obsidian or via Claude instead.
. "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

require RCLONE_REMOTE
require RCLONE_BACKUP_PATH

dest="$RCLONE_REMOTE:$RCLONE_BACKUP_PATH"
# Files this run would delete or replace are parked here instead, so a bad
# sync (an empty mirror, say) cannot silently destroy the backup.
attic="$RCLONE_REMOTE:$RCLONE_BACKUP_PATH-replaced/$(date -u +%Y-%m-%d)"

# Refuse to mirror an empty tree over a good backup.
if ! find "$VAULT_ROOT" -mindepth 2 -name '*.md' -print -quit | grep -q .; then
    echo "ERROR: no markdown found under $VAULT_ROOT; refusing to sync" >&2
    exit 1
fi

rclone sync "$VAULT_ROOT" "$dest" \
    --backup-dir "$attic" \
    --exclude '.obsidian/**' \
    --exclude '.trash/**' \
    --exclude '.livesync-mcp-*' \
    --create-empty-src-dirs \
    --transfers 8 \
    --checkers 16 \
    --log-level INFO

echo "Backed up $VAULT_ROOT -> $dest (replaced files parked in $attic)"
