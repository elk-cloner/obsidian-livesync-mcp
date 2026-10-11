#!/usr/bin/env bash
# Add a vault to the stack. Run it twice:
#
#   sudo ./scripts/add-vault.sh <name>
#
#   1st run  creates the vault's CouchDB database and prints a Setup URI for
#            the first device. Nothing else changes yet. Running it again
#            before that device has uploaded just prints a fresh URI.
#   2nd run  (after that device finished its first upload) wires the vault in:
#            VAULTS in .env, its folder in /srv/vaults, local history, the
#            GitHub repo if GIT_PUSH=github, and the bridge.
#
# The two passes exist because the first device must upload before the bridge
# connects: it writes the database's LiveSync settings, which the bridge reads
# (useRemoteTweaks). Re-running on a vault that is already added only re-checks
# everything, which is also how existing vaults get GitHub repos after
# GIT_PUSH=github is turned on.
. "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

usage() {
    echo "Usage: sudo $0 <vault-name>" >&2
    exit 2
}

[[ $# -eq 1 ]] || usage
name="$1"
if ! valid_vault_name "$name"; then
    echo "ERROR: invalid vault name '$name'. Use letters, digits, '.', '_' and '-', not starting with '.'." >&2
    exit 1
fi

require_root
require DOMAIN
require COUCHDB_USER
require COUCHDB_PASSWORD
require LIVESYNC_PASSPHRASE
# Fail before changing anything, not halfway through.
if github_enabled; then
    require_gh
fi

work="$VAULT_ROOT/$name"

# Upstream's Setup URI generator, pinned to a commit so a rebuild cannot
# silently change the settings devices receive. It runs from the raw URL with
# its own pinned npm dependencies.
SETUP_URI_REF="${SETUP_URI_REF:-14141446a14deab3353a8864dee41e44c372d006}"
SETUP_URI_GENERATOR="https://raw.githubusercontent.com/vrtmrz/obsidian-livesync/$SETUP_URI_REF/utils/flyio/generate_setupuri.ts"

# Print a Setup URI for this vault's first device.
#
# id_mode=legacy matters: newer LiveSync defaults to a random per-vault ID key,
# but livesync-bridge cannot be given that key, so it would compute different
# document IDs from the devices'. Legacy IDs derive from LIVESYNC_PASSPHRASE,
# which the bridge has. This also means there is no ID recovery code to keep.
print_setup_uri() {
    if ! command -v deno >/dev/null 2>&1; then
        echo "ERROR: Deno 2 is needed to generate the Setup URI (see docs/setup.md, section 2)." >&2
        exit 1
    fi
    hostname="https://couch.$DOMAIN" \
    username="$COUCHDB_USER" \
    password="$COUCHDB_PASSWORD" \
    database="$name" \
    passphrase="$LIVESYNC_PASSPHRASE" \
    id_mode=legacy \
        deno run --quiet --minimum-dependency-age=0 --allow-env "$SETUP_URI_GENERATOR"
}

# A previously removed copy must come back before the vault is re-added, so the
# bridge finds the files it remembers instead of an empty folder.
if [[ ! -d "$work" ]] && compgen -G "$REMOVED_ROOT/$name-*" >/dev/null; then
    echo "ERROR: '$name' was removed earlier; its files are parked in:" >&2
    ls -d "$REMOVED_ROOT/$name"-* >&2
    echo "Move the copy you want back first, e.g.: sudo mv <that folder> $work" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Pass 1: the database, then wait for the first device.
# ---------------------------------------------------------------------------
if ! vault_configured "$name"; then
    notes="$(db_note_count "$name")"

    if [[ "$notes" -lt 0 ]]; then
        "$REPO_DIR/scripts/couchdb-provision.sh" "$name"
        if [[ "$(db_note_count "$name")" -lt 0 ]]; then
            echo "==> creating database: $name"
            couch PUT "$name" >/dev/null
        fi
        notes=0
    fi

    if [[ "$notes" -eq 0 ]]; then
        echo
        echo "Database '$name' is ready. Setup URI for its FIRST device:"
        print_setup_uri
        cat <<EOF

The URI and its passphrase are only for setting up this one device, right
away; there is nothing here you need to keep. To connect it (docs/onboarding.md):

  1. On a desktop, open the vault in Obsidian:
       - new vault:      create an empty vault
       - existing notes: open that vault's folder
                         (if it lives in Google Drive, follow docs/migration.md first)
  2. Install Self-hosted LiveSync, choose to import a Setup URI, paste the URI
     above, and enter its passphrase. Do not set LiveSync up by hand instead.
  3. Let the first upload finish completely.

Then run this again to connect the vault to the server:

  sudo $0 $name

(Running it before the upload has finished just prints a fresh URI.)
EOF
        exit 0
    fi

    echo "==> database '$name' holds $notes document(s); connecting it to the server"
fi

# ---------------------------------------------------------------------------
# Pass 2: wire the vault in. Every step is safe to repeat.
# ---------------------------------------------------------------------------

# GitHub first: it is the step most likely to fail, and nothing has changed yet.
if github_enabled; then
    owner="$(github_owner)"
    if visibility="$(gh repo view "$owner/$name" --json visibility --jq .visibility 2>/dev/null)"; then
        echo "==> using existing GitHub repo $owner/$name ($visibility)"
        if [[ "$visibility" != "PRIVATE" ]]; then
            echo "WARN: $owner/$name is $visibility. Notes are pushed unencrypted; make it private." >&2
        fi
    else
        echo "==> creating PRIVATE GitHub repo $owner/$name for this vault's history"
        gh repo create "$owner/$name" --private \
            --description "Obsidian vault history, auto-committed by obsidian-livesync-mcp" >/dev/null
    fi
fi

if ! vault_configured "$name"; then
    set_vaults "$(printf '%s\n' $(vault_list) "$name" | xargs)"
    echo "==> added '$name' to VAULTS in $ENV_FILE"
fi

install -d -m 755 "$work"
own_by_vault_uid "$work"

"$REPO_DIR/scripts/gen-bridge-config.sh"
apply_bridge_config

# The bridge needs a moment to pull and decrypt everything.
echo "==> waiting for notes to appear in $work"
for _ in $(seq 1 30); do
    if find "$work" -type f -name '*.md' -print -quit | grep -q .; then
        count="$(find "$work" -type f -name '*.md' | wc -l | tr -d ' ')"
        echo "==> $count note(s) mirrored into $work"
        break
    fi
    sleep 2
done
if ! find "$work" -type f -name '*.md' -print -quit | grep -q .; then
    echo "WARN: no notes in $work yet. A brand-new vault stays empty until you write"
    echo "      a note; otherwise check: docker compose logs --tail=100 bridge"
fi

# First history commit, so it holds the notes the bridge just mirrored.
install -d -m 700 "$GIT_ROOT"
history_repo_init "$name"
history_commit "$name"
if github_enabled; then
    history_push "$name"
fi

cat <<EOF

'$name' is connected. Claude can now see it, and the timers include it.
Onboard your other devices from a fresh Setup URI (docs/onboarding.md);
they should download, not upload.
EOF
