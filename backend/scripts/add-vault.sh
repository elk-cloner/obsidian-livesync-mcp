#!/usr/bin/env bash
# Add a vault to the stack, in one run:
#
#   sudo ./scripts/add-vault.sh <name>              set up, wait, connect
#   sudo ./scripts/add-vault.sh <name> --no-wait    set up and print the URI only
#
#   1. Creates the vault's CouchDB database and prints a Setup URI for the
#      first device.
#   2. Waits while you set that device up, watching the database until its
#      first upload has settled.
#   3. Wires the vault in: VAULTS in .env, its folder in VAULT_ROOT, local
#      history, the GitHub repo if GIT_PUSH=github, and the bridge.
#
# The wait exists because the first device must upload before the bridge
# connects: it writes the database's LiveSync settings, which the bridge reads
# (useRemoteTweaks). Until step 3 only the database exists, so Ctrl+C while
# waiting leaves nothing half-done. Running the same command again resumes: an
# empty database gets a fresh URI and another wait; one that already holds
# notes (including a vault brought back after removal) connects straight away.
# With --no-wait, run it again once the first upload has finished.
#
# Re-running on a vault that is already added only re-checks everything, which
# is also how existing vaults get GitHub repos after GIT_PUSH=github is turned
# on.
. "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

# How users run this, from backend/ as the docs say. Used in every hint.
SELF="./scripts/add-vault.sh"

usage() {
    echo "Usage: sudo $SELF <vault-name> [--no-wait]" >&2
    exit 2
}

wait_for_device=1
name=""
for arg in "$@"; do
    case "$arg" in
        --no-wait) wait_for_device=0 ;;
        -*) usage ;;
        *)
            if [[ -n "$name" ]]; then usage; fi
            name="$arg"
            ;;
    esac
done
[[ -n "$name" ]] || usage
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

# Waiting for the first device. The database is polled every POLL_SECONDS.
# The upload counts as finished once neither the note count nor the database's
# update_seq has moved for SETTLE_SECONDS: LiveSync uploads in batches with
# short gaps between them, and 30 seconds of silence is far longer than those
# gaps. If a slow device does pause longer, nothing breaks: the bridge follows
# the database's changes feed, so it mirrors the rest as it arrives, and the
# next timer run commits it to history. The first device must connect within
# FIRST_UPLOAD_TIMEOUT; after that the script stops and asks for a re-run,
# which prints a fresh URI (they expire within days).
POLL_SECONDS="${POLL_SECONDS:-5}"
SETTLE_SECONDS="${SETTLE_SECONDS:-30}"
FIRST_UPLOAD_TIMEOUT="${FIRST_UPLOAD_TIMEOUT:-3600}"

# Print a Setup URI for this vault's first device. Only ever to the terminal.
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

# "<notes> <update_seq>" for this vault's database; fails if CouchDB could not
# be asked, so a network blip is neither progress nor silence.
db_progress() {
    local info notes
    info="$(couch GET "$name" 2>/dev/null)" || return 1
    notes="$(db_note_count "$name")"
    [[ "$notes" -ge 0 ]] || return 1
    printf '%s %s\n' "$notes" \
        "$(python3 -c 'import json, sys; print(json.loads(sys.argv[1])["update_seq"])' "$info")"
}

# Ctrl+C while waiting. Only the database exists at this point, and every
# step is safe to repeat, so a re-run simply carries on.
stopped_waiting() {
    cat <<EOF

Stopped waiting. Nothing has changed apart from the database existing.
To carry on, run the same command again:

  sudo $SELF $name

If no device has connected yet it prints a fresh URI and waits again; if the
first device has connected, it connects the vault straight away.
EOF
    exit 130
}

# Block until the first device connects, or give up after the timeout. Any
# write after the provisioner's counts too: update_seq moving from its value
# here, even if the device only rewrote the version document.
wait_for_first_device() {
    local waited=0 start now
    start="$(db_progress)" || start=""
    echo "==> waiting for the first device to connect (Ctrl+C to stop)"
    while :; do
        db_device_seen "$name" && break
        now="$(db_progress)" || now=""
        [[ -n "$start" && -n "$now" && "${now#* }" != "${start#* }" ]] && break
        if [[ $waited -ge $FIRST_UPLOAD_TIMEOUT ]]; then
            cat <<EOF

No device after $((FIRST_UPLOAD_TIMEOUT / 60)) minutes, so this stopped waiting. Nothing has
changed apart from the database existing. When the device is ready, run:

  sudo $SELF $name

It prints a fresh Setup URI and waits again.
EOF
            exit 1
        fi
        sleep "$POLL_SECONDS"
        waited=$((waited + POLL_SECONDS))
    done
    echo "==> first device connected: $(db_note_count "$name") note(s) so far"
}

# Block until the database has been quiet for SETTLE_SECONDS. Prints the
# document count at most every 30 seconds, so a long upload stays readable.
wait_for_upload_to_settle() {
    local state last="" quiet=0 shown="" shown_at=-30
    echo "==> waiting until the upload has been quiet for ${SETTLE_SECONDS}s"
    while [[ $quiet -lt $SETTLE_SECONDS ]]; do
        sleep "$POLL_SECONDS"
        state="$(db_progress)" || continue
        if [[ "$state" == "$last" ]]; then
            quiet=$((quiet + POLL_SECONDS))
        else
            quiet=0
            last="$state"
            if [[ "${state%% *}" != "$shown" && $((SECONDS - shown_at)) -ge 30 ]]; then
                shown="${state%% *}"
                shown_at=$SECONDS
                echo "    $shown document(s) so far"
            fi
        fi
    done
    echo "==> upload settled at ${last%% *} document(s); connecting the vault to the server"
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
# Steps 1 and 2: the database, then wait for the first device.
# ---------------------------------------------------------------------------
if ! vault_configured "$name"; then
    notes="$(db_note_count "$name")"

    if [[ "$notes" -lt 0 ]]; then
        "$BACKEND_DIR/scripts/couchdb-provision.sh" "$name"
        if [[ "$(db_note_count "$name")" -lt 0 ]]; then
            echo "==> creating database: $name"
            couch PUT "$name" >/dev/null
        fi
        notes=0
    fi

    if ! db_device_seen "$name"; then
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
EOF
        if [[ $wait_for_device -eq 0 ]]; then
            cat <<EOF

Then run this again, without --no-wait, to connect the vault to the server:

  sudo $SELF $name

(Running it before the device has connected just prints a fresh URI.)
EOF
            exit 0
        fi
        cat <<EOF

Keep this window open: this script watches the database and connects the
vault to the server by itself once the upload has been quiet for ${SETTLE_SECONDS}s.
Ctrl+C stops waiting without changing anything else; run the same command
again to carry on.

EOF
        trap stopped_waiting INT
        wait_for_first_device
        wait_for_upload_to_settle
        trap - INT
    elif [[ $wait_for_device -eq 1 ]]; then
        # A device was already here: a vault brought back after removal, or a
        # re-run after Ctrl+C. Make sure no device is still mid-upload first.
        echo "==> a device already connected to '$name'; it holds $notes note(s)"
        trap stopped_waiting INT
        wait_for_upload_to_settle
        trap - INT
    else
        echo "==> database '$name' holds $notes document(s); connecting it to the server"
    fi
fi

# ---------------------------------------------------------------------------
# Step 3: wire the vault in. Every step is safe to repeat.
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

make_vault_dir "$work"

"$BACKEND_DIR/scripts/gen-bridge-config.sh"
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

New vault? Put the knowledge vault schema into it (skip if already seeded):

  sudo ./scripts/seed-vault.sh $name
EOF
