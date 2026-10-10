#!/usr/bin/env bash
# Configure CouchDB for LiveSync and create one database per vault.
#
# Delegates to the upstream provisioner so the settings always match what the
# plugin expects, rather than a hand-maintained copy. Requires Deno 2 on the
# host. Idempotent: safe to re-run after adding a vault to VAULTS.
. "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

require COUCHDB_USER
require COUCHDB_PASSWORD
require DOMAIN

INIT="${INIT_SCRIPT:-$REPO_DIR/.cache/couchdb-init.sh}"
if [[ ! -x "$INIT" ]]; then
    mkdir -p "$(dirname "$INIT")"
    curl -fsSL -o "$INIT" \
        https://raw.githubusercontent.com/vrtmrz/obsidian-livesync/main/utils/couchdb/couchdb-init.sh
    chmod +x "$INIT"
fi

for vault in $(vault_list); do
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
