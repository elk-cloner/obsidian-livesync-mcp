#!/usr/bin/env bash
# Generate bridge/config.json from .env.
#
# Peers sharing a `group` replicate with each other, so each vault gets exactly
# one couchdb peer and one storage peer in a group of its own. Every couchdb
# peer repeats the same credentials and E2EE passphrase, so hand-editing the
# JSON is error-prone -- regenerate instead.
. "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

require COUCHDB_USER
require COUCHDB_PASSWORD
require LIVESYNC_PASSPHRASE

OUT="$REPO_DIR/bridge/config.json"

python3 - "$OUT" <<'PY'
import json, os, sys

vaults = os.environ["VAULTS"].split()
if not vaults:
    sys.exit("VAULTS is empty")

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
        "obfuscatePassphrase": os.environ.get("LIVESYNC_OBFUSCATE_PASSPHRASE", ""),
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
print(f"wrote {sys.argv[1]} with {len(vaults)} vault(s): {' '.join(vaults)}")
PY

chmod 600 "$OUT"
echo "Mode set to 600 -- this file contains the E2EE passphrase."

for vault in $(vault_list); do
    install -d -m 755 "$VAULT_ROOT/$vault"
done
echo "Ensured $VAULT_ROOT/<vault> exists for each vault."
