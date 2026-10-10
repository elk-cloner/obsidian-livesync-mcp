#!/usr/bin/env bash
# Commit every vault's current state to its local history repo, and push it to
# GitHub when GIT_PUSH=github.
#
# Local history (/srv/git/<vault>.git) is always on: it needs no account and
# gives a 15-minute undo for bad edits. The push is the optional off-server
# copy; GitHub login is the user's own `sudo gh auth login`. Repos are created
# by add-vault.sh, never here.
. "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

vaults="$(vault_list)"
if [[ -z "$vaults" ]]; then
    echo "No vaults configured; nothing to commit."
    exit 0
fi

for vault in $vaults; do
    if [[ ! -d "$VAULT_ROOT/$vault" ]]; then
        echo "skip $vault: $VAULT_ROOT/$vault does not exist" >&2
        continue
    fi

    history_repo_init "$vault"
    history_commit "$vault"

    # Push even when nothing new was committed, so a push that failed last
    # time (or history from before GitHub was turned on) catches up.
    if github_enabled; then
        history_push "$vault"
    fi
done
