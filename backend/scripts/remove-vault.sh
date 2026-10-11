#!/usr/bin/env bash
# Take a vault out of the stack without destroying anything by default.
#
#   sudo ./scripts/remove-vault.sh <name> [--purge]
#
# Default: final history commit (and push if GIT_PUSH=github), drop the vault
# from VAULTS and the bridge, and park its files in REMOVED_ROOT so
# Claude no longer sees it. The history repo, the GitHub repo and the CouchDB
# database are kept.
#
# --purge additionally deletes the CouchDB database. That is the last
# server-side encrypted copy and cannot be undone.
. "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

usage() {
    echo "Usage: sudo $0 <vault-name> [--purge]" >&2
    exit 2
}

purge=0
name=""
for arg in "$@"; do
    case "$arg" in
        --purge) purge=1 ;;
        -*) usage ;;
        *) [[ -z "$name" ]] && name="$arg" || usage ;;
    esac
done
[[ -n "$name" ]] || usage
if ! valid_vault_name "$name"; then
    echo "ERROR: invalid vault name '$name'." >&2
    exit 1
fi

require_root
require DOMAIN
require COUCHDB_USER
require COUCHDB_PASSWORD
require LIVESYNC_PASSPHRASE

work="$VAULT_ROOT/$name"

if ! vault_configured "$name" && [[ ! -d "$work" ]]; then
    if [[ "$purge" -eq 0 ]]; then
        echo "'$name' is not a configured vault and has no folder in $VAULT_ROOT; nothing to remove."
        echo "(If it only has a database from a first add-vault run, use --purge to delete that.)"
        exit 0
    fi
fi

echo "This removes '$name' from the server:"
echo "  - final history commit$(github_enabled && echo ' and push to GitHub')"
echo "  - drop it from VAULTS and the bridge (server-side syncing stops)"
echo "  - move $work to $REMOVED_ROOT/ (Claude stops seeing it)"
echo "  - keep $GIT_ROOT/$name.git and any GitHub repo"
if [[ "$purge" -eq 1 ]]; then
    echo "  - DELETE the CouchDB database '$name' (cannot be undone)"
else
    echo "  - keep the CouchDB database '$name'"
fi
read -r -p "Type the vault name to confirm: " answer
if [[ "$answer" != "$name" ]]; then
    echo "Cancelled; nothing changed."
    exit 1
fi

# 1. Last snapshot of the vault as it is now.
if [[ -d "$work" ]]; then
    install -d -m 700 "$GIT_ROOT"
    history_repo_init "$name"
    history_commit "$name"
    if github_enabled; then
        history_push "$name"
    fi
fi

# 2. Disconnect the bridge BEFORE touching the folder. A bridge still watching
#    it would read the move as "every note deleted" and push those deletions to
#    CouchDB, and from there to every device.
if vault_configured "$name"; then
    set_vaults "$(vault_list | { grep -vxF -- "$name" || true; } | xargs)"
    echo "==> removed '$name' from VAULTS in $ENV_FILE"
fi
"$BACKEND_DIR/scripts/gen-bridge-config.sh"
apply_bridge_config

# 3. Park the files outside VAULT_ROOT, where the MCP server does not look.
if [[ -d "$work" ]]; then
    install -d -m 755 "$REMOVED_ROOT"
    parked="$REMOVED_ROOT/$name-$(date -u +%Y%m%dT%H%M%SZ)"
    mv "$work" "$parked"
    echo "==> moved $work to $parked"
fi

# 4. Optionally delete the database.
if [[ "$purge" -eq 1 ]]; then
    read -r -p "Really delete CouchDB database '$name'? Type 'delete': " answer
    if [[ "$answer" == "delete" ]]; then
        if couch DELETE "$name" >/dev/null 2>&1; then
            echo "==> deleted CouchDB database '$name'"
        else
            echo "WARN: could not delete database '$name' (already gone?)" >&2
        fi
    else
        echo "Kept the CouchDB database '$name'."
    fi
fi

cat <<EOF

'$name' is removed from the server. Still to do by hand:
  - On each device, disable Self-hosted LiveSync for this vault (or delete the
    local vault). Devices still syncing would recreate it in CouchDB.
  - The next nightly backup moves its Google Drive copy into the dated
    '${RCLONE_BACKUP_PATH:-ObsidianBackup}-replaced' folder automatically.
To bring it back later: move the parked folder back to $work, then run
  sudo ./scripts/add-vault.sh $name
EOF
