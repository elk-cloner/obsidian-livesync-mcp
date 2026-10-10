# Shared bootstrap for every script here. Sourced, not executed.
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_DIR/.env}"
VAULT_ROOT="${VAULT_ROOT:-/srv/vaults}"
GIT_ROOT="${GIT_ROOT:-/srv/git}"
# Where remove-vault.sh parks a vault's files. Outside VAULT_ROOT on purpose:
# the MCP server lists every directory under VAULT_ROOT as a vault.
REMOVED_ROOT="${REMOVED_ROOT:-/srv/vaults-removed}"
# The uid both the bridge and the MCP server run as. Vault folders must be
# owned by it, or both containers can read but not write.
VAULT_UID="${VAULT_UID:-1993}"

if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
else
    echo "ERROR: $ENV_FILE is missing (copy .env.example)" >&2
    exit 1
fi

require() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        echo "ERROR: $name is not set in .env" >&2
        exit 1
    fi
}

# The management scripts write to root-owned places (/srv/git, /srv/vaults
# ownership, .env), and the timers run as root, so run them with sudo.
# ALLOW_NON_ROOT=1 skips the check for local testing against temp dirs.
require_root() {
    if [[ $EUID -ne 0 && -z "${ALLOW_NON_ROOT:-}" ]]; then
        echo "ERROR: run this with sudo." >&2
        exit 1
    fi
}

# Hand files to the uid the bridge and MCP containers run as. A no-op when not
# root (local testing), where chown would fail anyway.
own_by_vault_uid() {
    if [[ $EUID -eq 0 ]]; then
        chown "$VAULT_UID:$VAULT_UID" "$@"
    fi
}

# One vault per line. No vaults is a normal state, not an error: the backend
# runs without any, and add-vault.sh fills this in.
vault_list() {
    # shellcheck disable=SC2086
    [[ -n "${VAULTS:-}" ]] && printf '%s\n' $VAULTS
    return 0
}

vault_configured() {
    local name="$1" vault
    for vault in $(vault_list); do
        [[ "$vault" == "$name" ]] && return 0
    done
    return 1
}

# Vault names become database names, directory names and repo names, so keep
# them to a portable set and never let one start with a dot.
valid_vault_name() {
    [[ "$1" =~ ^[A-Za-z0-9_-][A-Za-z0-9._-]*$ ]]
}

# Rewrite the VAULTS= line in .env, leaving every other line untouched, and
# update this process's copy to match.
set_vaults() {
    local list="$1"
    python3 - "$ENV_FILE" "$list" <<'PY'
import os, re, sys
path, value = sys.argv[1], sys.argv[2]
text = open(path).read()
line = f'VAULTS="{value}"' if value else "VAULTS="
if re.search(r"^VAULTS=.*$", text, flags=re.M):
    text = re.sub(r"^VAULTS=.*$", lambda _: line, text, count=1, flags=re.M)
else:
    text = text.rstrip("\n") + "\n" + line + "\n"
mode = os.stat(path).st_mode & 0o777
with open(path, "w") as handle:
    handle.write(text)
os.chmod(path, mode)
PY
    VAULTS="$list"
}

# curl against CouchDB through Caddy, the same endpoint devices use.
# Usage: couch <METHOD> <path> [extra curl args...]
couch() {
    require COUCHDB_USER
    require COUCHDB_PASSWORD
    require DOMAIN
    local method="$1" path="$2"
    shift 2
    curl -fsS -X "$method" -u "$COUCHDB_USER:$COUCHDB_PASSWORD" \
        "https://couch.$DOMAIN/$path" "$@"
}

# ---------------------------------------------------------------------------
# Git history. Local history is always on; pushing to GitHub is opt-in.
# ---------------------------------------------------------------------------

github_enabled() {
    [[ "${GIT_PUSH:-}" == "github" ]]
}

gh_logged_in() {
    command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1
}

require_gh() {
    if ! command -v gh >/dev/null 2>&1; then
        echo "ERROR: GIT_PUSH=github needs the GitHub CLI (gh), which is not installed." >&2
        exit 1
    fi
    if ! gh_logged_in; then
        echo "ERROR: GitHub CLI is not logged in. Run 'sudo gh auth login', then retry." >&2
        exit 1
    fi
}

# The account or organization that holds one repo per vault.
github_owner() {
    if [[ -n "${GIT_REMOTE_OWNER:-}" ]]; then
        printf '%s\n' "$GIT_REMOTE_OWNER"
    else
        gh api user --jq .login
    fi
}

# Run git against a vault's out-of-tree history repo. The git directory lives
# OUTSIDE the synced tree, so the bridge never sees a .git folder and never
# tries to replicate it to devices.
vault_git() {
    local vault="$1"
    shift
    command git --git-dir="$GIT_ROOT/$vault.git" --work-tree="$VAULT_ROOT/$vault" "$@"
}

history_repo_init() {
    local vault="$1" repo="$GIT_ROOT/$1.git"
    [[ -d "$repo" ]] && return 0
    echo "==> initialising history repo for $vault"
    install -d -m 700 "$repo"
    vault_git "$vault" init --quiet --initial-branch=main
    # Device config is not synced, so it is never in the mirror; .trash is
    # kept out of history because trash_note already preserves the content.
    printf '%s\n' '.obsidian/' '.trash/' '.livesync-mcp-*' > "$repo/info/exclude"
}

# Commit whatever changed in one vault. Prints a line only when it committed.
history_commit() {
    local vault="$1" changed
    vault_git "$vault" add -A
    vault_git "$vault" diff --cached --quiet && return 0
    changed="$(vault_git "$vault" diff --cached --numstat | wc -l | tr -d ' ')"
    vault_git "$vault" \
        -c user.name="${GIT_AUTHOR_NAME:-vault-bot}" \
        -c user.email="${GIT_AUTHOR_EMAIL:-vault-bot@localhost}" \
        commit --quiet -m "auto: $(date -u +%Y-%m-%dT%H:%M:%SZ) ($changed file(s))"
    echo "==> $vault: committed $changed file(s)"
}

# Point a history repo at its GitHub repo and push, using gh's login over
# HTTPS. Never fails the caller: local history is the primary artefact and
# the push is only the off-server copy.
history_push() {
    local vault="$1" owner
    if ! gh_logged_in; then
        echo "WARN $vault: GIT_PUSH=github but gh is not logged in; run 'sudo gh auth login'" >&2
        return 0
    fi
    owner="$(github_owner)"
    local url="https://github.com/$owner/$vault.git"
    if vault_git "$vault" remote get-url origin >/dev/null 2>&1; then
        vault_git "$vault" remote set-url origin "$url"
    else
        vault_git "$vault" remote add origin "$url"
    fi
    vault_git "$vault" config credential.https://github.com.helper '!gh auth git-credential'
    if ! vault_git "$vault" rev-parse --verify --quiet HEAD >/dev/null; then
        return 0   # nothing committed yet
    fi
    if ! vault_git "$vault" push --quiet origin main 2>&1; then
        echo "WARN $vault: push to $url failed; local history is intact" >&2
    fi
}

# ---------------------------------------------------------------------------
# Bridge and CouchDB, for add-vault.sh / remove-vault.sh.
# ---------------------------------------------------------------------------

compose() {
    docker compose --project-directory "$REPO_DIR" -f "$REPO_DIR/compose.yaml" "$@"
}

# Apply a regenerated bridge/config.json. The bridge reads it only at start,
# so a running bridge is restarted; with no vaults left it is stopped.
apply_bridge_config() {
    if [[ -z "$(vault_list)" ]]; then
        echo "==> no vaults left; stopping the bridge"
        compose stop bridge
    elif [[ -n "$(compose ps --status running -q bridge)" ]]; then
        echo "==> restarting the bridge"
        compose restart bridge
    else
        echo "==> starting the bridge"
        compose up -d bridge
    fi
}

# Number of note documents in a vault's database (design docs excluded), or
# -1 if the database does not exist.
db_note_count() {
    local info design
    if ! info="$(couch GET "$1" 2>/dev/null)"; then
        echo -1
        return 0
    fi
    design="$(couch GET "$1/_design_docs" 2>/dev/null || echo '{"rows": []}')"
    python3 -c 'import json, sys
info, design = json.loads(sys.argv[1]), json.loads(sys.argv[2])
print(info["doc_count"] - len(design.get("rows", [])))' "$info" "$design"
}
