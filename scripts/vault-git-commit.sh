#!/usr/bin/env bash
# Commit every vault's current state and push off-server.
#
# The git directory lives OUTSIDE the synced tree, driven by --git-dir and
# --work-tree, so the bridge never sees a .git folder and never tries to
# replicate it to devices.
. "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

require GIT_REMOTE_OWNER

export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-vault-bot}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-vault-bot@localhost}"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Thin wrapper so every git call targets the out-of-tree history repo. Reads
# $repo and $work from the loop below.
g() { command git --git-dir="$repo" --work-tree="$work" "$@"; }

for vault in $(vault_list); do
    work="$VAULT_ROOT/$vault"
    repo="$GIT_ROOT/$vault.git"

    if [[ ! -d "$work" ]]; then
        echo "skip $vault: $work does not exist" >&2
        continue
    fi

    if [[ ! -d "$repo" ]]; then
        echo "==> initialising history repo for $vault"
        install -d -m 700 "$repo"
        g init --quiet --initial-branch=main
        g remote add origin "git@github.com:$GIT_REMOTE_OWNER/$vault.git"
        # Device config is not synced, so it is never in the mirror; .trash is
        # kept out of history because trash_note already preserves the content.
        printf '%s\n' '.obsidian/' '.trash/' '.livesync-mcp-*' \
            > "$repo/info/exclude"
    fi

    g add -A
    if g diff --cached --quiet; then
        continue
    fi

    changed="$(g diff --cached --numstat | wc -l | tr -d ' ')"
    g commit --quiet -m "auto: $stamp ($changed file(s))"
    echo "==> $vault: committed $changed file(s)"

    # A missing or unreachable remote must not fail the whole run -- the local
    # history is the primary artefact and the push is only the off-server copy.
    if ! g push --quiet origin main; then
        echo "WARN $vault: push to origin failed; local history is intact" >&2
    fi
done
