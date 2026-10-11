#!/usr/bin/env bash
# Read-only health check of a running install.
#
#   sudo ./scripts/doctor.sh
#
# Prints one line per check: ✅ ok, ⚠️  warning, ❌ fail, with a hint and the
# document to read when something is wrong. Exits 1 if any check fails, 0
# otherwise (warnings included). It changes nothing, so it is safe to run at
# any time; bootstrap.sh runs it at the end.
#
# It needs sudo even though it only reads: .env is mode 600 and owned by root,
# bridge/config.json likewise belongs to the bridge's uid, and the docker,
# systemd and rclone checks look at root's daemon, units and rclone config.
#
# A fresh install with no vaults is a normal state: the per-vault checks are
# then skipped.

# _common.sh stops at a missing .env; report that as a failed check instead.
_env="${ENV_FILE:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/.env}"
if [[ ! -f "$_env" ]]; then
    echo "❌ .env: $_env is missing — run: sudo ./scripts/bootstrap.sh (docs/setup.md)"
    exit 1
fi
. "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

require_root

failures=0
warnings=0

ok() { echo "✅ $*"; }
warn() { echo "⚠️  $*"; warnings=$((warnings + 1)); }
fail() { echo "❌ $*"; failures=$((failures + 1)); }

# Portable stat: GNU on the server, BSD when testing on a Mac.
file_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
file_uid() { stat -c %u "$1" 2>/dev/null || stat -f %u "$1"; }

# Every network check gives up after this many seconds.
TIMEOUT="${DOCTOR_TIMEOUT:-10}"

vaults="$(vault_list | xargs)"

# ---------------------------------------------------------------------------
# .env
# ---------------------------------------------------------------------------
mode="$(file_mode "$ENV_FILE")"
if [[ "$mode" == "600" ]]; then
    ok ".env: mode 600"
else
    fail ".env: mode $mode, must be 600 — run: sudo chmod 600 $ENV_FILE (docs/runbook.md)"
fi

missing=()
for key in DOMAIN ACME_EMAIL ALLOWED_EMAIL COUCHDB_USER COUCHDB_PASSWORD \
        LIVESYNC_PASSPHRASE GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET \
        JWT_SIGNING_KEY OAUTH_STORAGE_ENCRYPTION_KEY RCLONE_REMOTE RCLONE_BACKUP_PATH; do
    [[ -n "${!key:-}" ]] || missing+=("$key")
done
# The placeholders from .env.example count as unset.
[[ "${DOMAIN:-}" == "example.com" ]] && missing+=("DOMAIN (still example.com)")
if [[ ${#missing[@]} -eq 0 ]]; then
    ok ".env: all required values are set"
else
    fail ".env: not set: ${missing[*]} — run: sudo ./scripts/bootstrap.sh (docs/setup.md)"
fi

# ---------------------------------------------------------------------------
# Containers
# ---------------------------------------------------------------------------
docker_ok=0
if ! command -v docker >/dev/null 2>&1; then
    fail "docker: not installed — see docs/setup.md, section 2"
elif ! docker info >/dev/null 2>&1; then
    fail "docker: the daemon is not reachable — run: systemctl status docker"
else
    docker_ok=1
fi

running() {
    [[ $docker_ok -eq 1 && -n "$(compose ps --status running -q "$1" 2>/dev/null)" ]]
}

if [[ $docker_ok -eq 1 ]]; then
    for service in couchdb caddy mcp; do
        if running "$service"; then
            ok "container $service: running"
        else
            fail "container $service: not running — run: docker compose up -d $service; docker compose logs --tail=100 $service"
        fi
    done

    if [[ -n "$vaults" ]]; then
        if running bridge; then
            ok "container bridge: running"
        else
            fail "container bridge: not running, but VAULTS is set — run: docker compose up -d bridge; docker compose logs --tail=100 bridge (docs/runbook.md)"
        fi
    elif running bridge; then
        warn "container bridge: running with no vaults configured — run: docker compose stop bridge"
    else
        ok "container bridge: stopped (no vaults yet)"
    fi

    if running couchdb; then
        health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' \
            "$(compose ps -q couchdb)" 2>/dev/null || true)"
        case "$health" in
            healthy) ok "couchdb: healthy" ;;
            starting) warn "couchdb: health check still starting — run this again in a minute" ;;
            *) fail "couchdb: health is '${health:-unknown}' — run: docker compose logs --tail=100 couchdb" ;;
        esac
    fi
fi

# ---------------------------------------------------------------------------
# CouchDB over TLS
# ---------------------------------------------------------------------------
couch_ok=0
if [[ -z "${DOMAIN:-}" || -z "${COUCHDB_PASSWORD:-}" ]]; then
    fail "couchdb over TLS: skipped, DOMAIN or COUCHDB_PASSWORD is not set"
elif couch GET _up --max-time "$TIMEOUT" >/dev/null 2>&1; then
    couch_ok=1
    ok "couchdb over TLS: https://couch.$DOMAIN/_up answers"
else
    fail "couchdb over TLS: https://couch.$DOMAIN/_up does not answer — check DNS, then: docker compose logs --tail=100 caddy (docs/runbook.md)"
fi

if [[ -n "$vaults" && $couch_ok -eq 1 ]]; then
    if dbs="$(couch GET _all_dbs --max-time "$TIMEOUT" 2>/dev/null)"; then
        for vault in $vaults; do
            if python3 -c 'import json, sys; sys.exit(sys.argv[2] not in json.loads(sys.argv[1]))' \
                    "$dbs" "$vault"; then
                ok "vault $vault: database exists"
            else
                fail "vault $vault: no database — run: sudo ./scripts/add-vault.sh $vault (docs/vaults.md)"
            fi
        done
    else
        fail "couchdb: could not list databases — check COUCHDB_USER and COUCHDB_PASSWORD"
    fi
fi

# ---------------------------------------------------------------------------
# Bridge config and logs
# ---------------------------------------------------------------------------
config="$BACKEND_DIR/bridge/config.json"
if [[ -d "$config" ]]; then
    fail "bridge config: $config is a directory (Docker made it) — run: sudo rmdir $config && sudo ./scripts/gen-bridge-config.sh"
elif [[ ! -f "$config" ]]; then
    fail "bridge config: $config is missing — run: sudo ./scripts/gen-bridge-config.sh"
elif ! peers="$(python3 -c 'import json, sys
peers = json.load(open(sys.argv[1]))["peers"]
print(" ".join(sorted(p["database"] for p in peers if p.get("type") == "couchdb")))' "$config" 2>/dev/null)"; then
    fail "bridge config: $config cannot be read or parsed — run: sudo ./scripts/gen-bridge-config.sh"
elif [[ "$peers" == "$(vault_list | LC_ALL=C sort | xargs)" ]]; then
    ok "bridge config: matches VAULTS (${vaults:-no vaults})"
else
    fail "bridge config: has '${peers}', VAULTS has '${vaults}' — run: sudo ./scripts/gen-bridge-config.sh && docker compose restart bridge"
fi

if [[ -n "$vaults" ]] && running bridge; then
    errors="$(compose logs --since 15m --no-color bridge 2>&1 | grep -Eic 'error|EACCES' || true)"
    if [[ "$errors" -eq 0 ]]; then
        ok "bridge logs: no errors in the last 15 minutes"
    else
        warn "bridge logs: $errors line(s) with 'error' or 'EACCES' in the last 15 minutes — run: docker compose logs --since 15m bridge (docs/runbook.md)"
    fi
fi

# ---------------------------------------------------------------------------
# Folders
# ---------------------------------------------------------------------------
if [[ ! -d "$VAULT_ROOT" ]]; then
    fail "folders: $VAULT_ROOT is missing — run: sudo ./scripts/bootstrap.sh (docs/setup.md, section 4)"
elif [[ "$(file_uid "$VAULT_ROOT")" != "$VAULT_UID" ]]; then
    fail "folders: $VAULT_ROOT is not owned by uid $VAULT_UID — run: sudo chown $VAULT_UID:$VAULT_UID $VAULT_ROOT"
else
    ok "folders: $VAULT_ROOT exists, owned by uid $VAULT_UID"
fi

for vault in $vaults; do
    work="$VAULT_ROOT/$vault"
    if [[ ! -d "$work" ]]; then
        fail "vault $vault: $work is missing — run: sudo ./scripts/add-vault.sh $vault"
    elif [[ "$(file_uid "$work")" != "$VAULT_UID" ]]; then
        fail "vault $vault: $work is not owned by uid $VAULT_UID — run: sudo chown -R $VAULT_UID:$VAULT_UID $work"
    else
        ok "vault $vault: folder exists, owned by uid $VAULT_UID"
    fi
done

# ---------------------------------------------------------------------------
# MCP server and OAuth discovery, as claude.ai sees them
# ---------------------------------------------------------------------------
if [[ -n "${DOMAIN:-}" ]]; then
    mcp="https://mcp.$DOMAIN"
    headers="$(curl -sS -o /dev/null -D - --max-time "$TIMEOUT" "$mcp/mcp" 2>/dev/null || true)"
    status="$(head -n 1 <<< "$headers" | awk '{print $2}')"
    if [[ "$status" == "401" ]] && grep -qi '^www-authenticate:.*resource_metadata' <<< "$headers"; then
        ok "mcp: $mcp/mcp answers 401 with resource_metadata"
    else
        fail "mcp: $mcp/mcp answered '${status:-nothing}', want 401 with resource_metadata — run: docker compose logs --tail=100 mcp (docs/runbook.md)"
    fi

    resource="$(curl -fsS --max-time "$TIMEOUT" "$mcp/.well-known/oauth-protected-resource/mcp" 2>/dev/null |
        jq -r '.resource // empty' 2>/dev/null || true)"
    if [[ "$resource" == "$mcp/mcp" ]]; then
        ok "mcp: protected resource metadata names $mcp/mcp"
    else
        fail "mcp: protected resource is '${resource:-missing}', want $mcp/mcp — check DOMAIN, then: docker compose up -d mcp (docs/runbook.md)"
    fi

    if curl -fsS --max-time "$TIMEOUT" "$mcp/.well-known/oauth-authorization-server" 2>/dev/null |
            jq -e '(.code_challenge_methods_supported | index("S256")) and .registration_endpoint' \
            >/dev/null 2>&1; then
        ok "mcp: authorization server metadata has S256 and a registration endpoint"
    else
        fail "mcp: authorization server metadata lacks S256 or a registration endpoint — run: docker compose logs --tail=100 mcp (docs/runbook.md)"
    fi
fi

# ---------------------------------------------------------------------------
# Timers
# ---------------------------------------------------------------------------
if ! command -v systemctl >/dev/null 2>&1; then
    fail "timers: systemctl not found, cannot check them"
else
    for timer in vault-git vault-backup vault-staleness; do
        if ! systemctl is-enabled --quiet "$timer.timer" 2>/dev/null; then
            fail "timer $timer: not enabled — run: sudo ./scripts/install-timers.sh"
            continue
        fi
        if ! systemctl is-active --quiet "$timer.timer"; then
            fail "timer $timer: enabled but not active, so it has no next run — run: sudo systemctl start $timer.timer"
            continue
        fi
        started="$(systemctl show -p ExecMainStartTimestamp --value "$timer.service" 2>/dev/null || true)"
        result="$(systemctl show -p Result --value "$timer.service" 2>/dev/null || true)"
        if [[ -z "$started" || "$started" == "n/a" ]]; then
            warn "timer $timer: active, but the service has not run yet — normal right after install"
        elif [[ "$result" == "success" ]]; then
            ok "timer $timer: active, last run succeeded ($started)"
        elif [[ "$timer" == "vault-staleness" ]]; then
            warn "timer $timer: last check reported a problem — run: ./scripts/bridge-staleness-check.sh (docs/runbook.md)"
        else
            fail "timer $timer: last run ended with '$result' — run: journalctl -u $timer.service -n 50 (docs/runbook.md)"
        fi
    done
fi

# ---------------------------------------------------------------------------
# History
# ---------------------------------------------------------------------------
for vault in $vaults; do
    repo="$GIT_ROOT/$vault.git"
    if [[ ! -d "$repo" ]]; then
        fail "vault $vault: no history repo at $repo — run: sudo ./scripts/add-vault.sh $vault"
    elif ! last="$(git --git-dir="$repo" log -1 --format=%ct 2>/dev/null)" || [[ -z "$last" ]]; then
        fail "vault $vault: history repo has no commit — run: sudo ./scripts/vault-git-commit.sh"
    else
        age=$(( $(date +%s) - last ))
        if [[ $age -gt 3600 ]]; then
            warn "vault $vault: last history commit $((age / 3600)) h ago — normal if nobody edited the vault since"
        else
            ok "vault $vault: last history commit $((age / 60)) min ago"
        fi
    fi
done

# ---------------------------------------------------------------------------
# Backup remote and disk space
# ---------------------------------------------------------------------------
if ! command -v rclone >/dev/null 2>&1; then
    warn "rclone: not installed, so there is no backup — see docs/setup.md, section 2"
elif rclone listremotes 2>/dev/null | grep -qxF "${RCLONE_REMOTE:-}:"; then
    ok "rclone: remote '$RCLONE_REMOTE' is configured"
else
    warn "rclone: no remote '${RCLONE_REMOTE:-}' — run: sudo rclone config (docs/setup.md, section 8)"
fi

# The nearest folder that exists, so the check works before VAULT_ROOT does.
disk_dir="$VAULT_ROOT"
while [[ ! -d "$disk_dir" ]]; do disk_dir="$(dirname -- "$disk_dir")"; done
free_kb="$(df -Pk "$disk_dir" | awk 'NR == 2 {print $4}')"
free_mb=$((free_kb / 1024))
if [[ $free_mb -lt 500 ]]; then
    fail "disk: only $free_mb MB free for $VAULT_ROOT — free some space now"
elif [[ $free_mb -lt 2048 ]]; then
    warn "disk: $free_mb MB free for $VAULT_ROOT — less than 2 GB"
else
    ok "disk: $((free_mb / 1024)) GB free for $VAULT_ROOT"
fi

echo
if [[ $failures -gt 0 ]]; then
    echo "$failures check(s) failed, $warnings warning(s). See docs/runbook.md."
    exit 1
fi
echo "All checks passed$([[ $warnings -gt 0 ]] && echo ", with $warnings warning(s)")."
