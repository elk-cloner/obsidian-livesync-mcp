#!/usr/bin/env bash
# Generate bridge/config.json from .env.
#
# Peers sharing a `group` replicate with each other, so each vault gets exactly
# one couchdb peer and one storage peer in a group of its own. Every couchdb
# peer repeats the same credentials and E2EE passphrase, so hand-editing the
# JSON is error-prone -- regenerate instead.
#
# With no vaults configured it writes an empty peer list, so config.json always
# exists as a file. (If it is missing when the bridge starts, Docker silently
# creates a directory in its place.) add-vault.sh and remove-vault.sh call this.
. "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

require_root
require COUCHDB_USER
require COUCHDB_PASSWORD
require LIVESYNC_PASSPHRASE

OUT="$REPO_DIR/bridge/config.json"

python3 - "$OUT" <<'PY'
import json, os, sys

vaults = os.environ.get("VAULTS", "").split()

peers = []
for vault in vaults:
    peers.append({
        "type": "couchdb",
        "name": f"{vault}-db",
        "group": vault,
        "url": "http://couchdb:5984",
        "database": vault,
        "username": os.environ["COUCHDB_USER"],
        "password": os.environ["COUCHDB_PASSWORD"],
        "passphrase": os.environ["LIVESYNC_PASSPHRASE"],
        # Setup URIs from add-vault.sh turn path obfuscation on and key it with
        # the E2EE passphrase; the bridge refuses to start without a match.
        "obfuscatePassphrase": os.environ.get("LIVESYNC_OBFUSCATE_PASSPHRASE")
            or os.environ["LIVESYNC_PASSPHRASE"],
        # Whole vault, not a subfolder.
        "baseDir": "",
        "useRemoteTweaks": True,
    })
    peers.append({
        "type": "storage",
        "name": f"{vault}-files",
        "group": vault,
        # Must start with data/ to land inside the container's mounted volume,
        # which maps to /srv/vaults on the host.
        "baseDir": f"data/vaults/{vault}/",
        "scanOfflineChanges": True,
        "useChokidar": True,
    })

with open(sys.argv[1], "w") as handle:
    json.dump({"peers": peers}, handle, indent=2)
    handle.write("\n")
print(f"wrote {sys.argv[1]} with {len(vaults)} vault(s): {' '.join(vaults) or '(none)'}")
PY

# Mode 600 because it holds the E2EE passphrase, owned by the bridge's uid so
# the container (which never runs as root) can still read it.
chmod 600 "$OUT"
own_by_vault_uid "$OUT"
echo "Mode set to 600$([[ $EUID -eq 0 ]] && echo ", owned by uid $VAULT_UID") -- this file contains the E2EE passphrase."

for vault in $(vault_list); do
    install -d -m 755 "$VAULT_ROOT/$vault"
    own_by_vault_uid "$VAULT_ROOT/$vault"
done
