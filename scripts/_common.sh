# Shared bootstrap for every script here. Sourced, not executed.
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_ROOT="${VAULT_ROOT:-/srv/vaults}"
GIT_ROOT="${GIT_ROOT:-/srv/git}"

if [[ -f "$REPO_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    . "$REPO_DIR/.env"
    set +a
else
    echo "ERROR: $REPO_DIR/.env is missing (copy .env.example)" >&2
    exit 1
fi

require() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        echo "ERROR: $name is not set in .env" >&2
        exit 1
    fi
}

vault_list() {
    require VAULTS
    # shellcheck disable=SC2086
    printf '%s\n' $VAULTS
}
