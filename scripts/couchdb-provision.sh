#!/usr/bin/env bash
# Configure CouchDB for LiveSync and create a vault's database.
#
# Usage: couchdb-provision.sh [vault]
#   With a vault name, provisions just that one (add-vault.sh does this).
#   Without, provisions every vault in VAULTS; none configured is fine.
#
# Delegates to the upstream provisioner so the settings always match what the
# plugin expects, rather than a hand-maintained copy. Requires Deno 2 on the
# host. Idempotent: safe to re-run.
. "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

require COUCHDB_USER
require COUCHDB_PASSWORD
require DOMAIN

if [[ $# -gt 0 ]]; then
    targets="$1"
    if ! valid_vault_name "$targets"; then
        echo "ERROR: invalid vault name '$targets' (use letters, digits, . _ -)" >&2
        exit 1
    fi
else
    targets="$(vault_list)"
fi

if [[ -z "$targets" ]]; then
    echo "No vaults configured; nothing to provision. Add one with ./scripts/add-vault.sh <name>."
    exit 0
fi

INIT="${INIT_SCRIPT:-$REPO_DIR/.cache/couchdb-init.sh}"
if [[ ! -x "$INIT" ]]; then
    mkdir -p "$(dirname "$INIT")"
    curl -fsSL -o "$INIT" \
        https://raw.githubusercontent.com/vrtmrz/obsidian-livesync/main/utils/couchdb/couchdb-init.sh
    chmod +x "$INIT"
fi

for vault in $targets; do
    echo "==> provisioning database: $vault"
    hostname="https://couch.$DOMAIN" \
    username="$COUCHDB_USER" \
    password="$COUCHDB_PASSWORD" \
    database="$vault" \
        "$INIT"
done

echo
echo "Done. Verify with:"
echo "  curl -fsS -u \"\$COUCHDB_USER:\$COUCHDB_PASSWORD\" https://couch.$DOMAIN/_all_dbs"
