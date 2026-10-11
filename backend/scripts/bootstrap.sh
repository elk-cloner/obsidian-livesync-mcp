#!/usr/bin/env bash
# Set up the backend on a fresh server, with no vaults, in one run:
#
#   sudo ./scripts/bootstrap.sh              set up, asking only for what is missing
#   sudo ./scripts/bootstrap.sh --dry-run    report what it would do; change nothing
#
# It automates docs/setup.md, sections 2 to 9: checks the tools, fills in .env
# (asking for the domain, emails and Google OAuth client, generating the
# random secrets and the LiveSync passphrase), checks DNS, creates the
# folders, starts CouchDB and Caddy, writes the bridge config, starts the MCP
# server and checks its OAuth discovery, installs the timers, and finally runs
# doctor.sh.
#
# Safe to re-run: every step checks first and skips what is done. It never
# changes a value that is already set in .env (the example placeholders such
# as example.com count as unset), and `docker compose up -d` leaves running
# containers alone unless their configuration changed. If a step fails, fix
# what it says and run it again; it carries on from there.
#
# Secrets are written to .env only, and the passphrase is shown once.
set -euo pipefail

# How users run this, from backend/ as the docs say. Used in every hint.
SELF="./scripts/bootstrap.sh"

usage() {
    cat <<EOF
Usage: sudo $SELF [--dry-run]

Sets up the backend (docs/setup.md) and asks only for values .env lacks.
Safe to re-run.

  --dry-run   report what each step would do; change nothing, ask nothing
  --help      show this help
EOF
}

dry_run=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) dry_run=1 ;;
        -h | --help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

# _common.sh needs .env, so the root check and creating .env come first.
backend="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$backend/.env}"
export ENV_FILE
if [[ $EUID -ne 0 && -z "${ALLOW_NON_ROOT:-}" ]]; then
    echo "ERROR: run this with sudo." >&2
    exit 1
fi

env_target="$ENV_FILE"
if [[ -f "$ENV_FILE" ]]; then
    env_state="exists"
elif [[ $dry_run -eq 1 ]]; then
    env_state="would create it from .env.example (mode 600)"
    # Read the example instead, to report what would be asked.
    ENV_FILE="$backend/.env.example"
else
    # install sets mode 600 as it copies, so the file is never readable by others.
    install -m 600 "$backend/.env.example" "$ENV_FILE"
    env_state="created from .env.example (mode 600)"
fi

# shellcheck source=_common.sh
. "$backend/scripts/_common.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

step() { echo; echo "==> $*"; }
would() { echo "    would: $*"; }

# Prompts read from the terminal, so they work even when stdin is a pipe.
ask() {
    local prompt="$1" default="${2:-}" reply
    [[ -n "$default" ]] && prompt="$prompt [$default]"
    read -r -p "$prompt: " reply </dev/tty || { echo >&2; echo "ERROR: no terminal to ask on." >&2; exit 1; }
    printf '%s\n' "${reply:-$default}"
}

# Hidden input; the newline after it goes to the terminal, not the value.
ask_secret() {
    local reply
    read -r -s -p "$1: " reply </dev/tty || { echo >&2; echo "ERROR: no terminal to ask on." >&2; exit 1; }
    echo >&2
    printf '%s\n' "$reply"
}

ask_yes_no() {
    local reply
    reply="$(ask "$1 [y/N]")"
    [[ "$reply" == [yY] || "$reply" == [yY][eE][sS] ]]
}

# The placeholders .env.example ships with. They are not real values.
placeholder() {
    case "$1" in
        DOMAIN) [[ "$2" == "example.com" ]] ;;
        ACME_EMAIL) [[ "$2" == "you@example.com" ]] ;;
        ALLOWED_EMAIL) [[ "$2" == "you@gmail.com" ]] ;;
        *) return 1 ;;
    esac
}

# True if KEY has no real value yet.
unset_value() {
    local value
    value="$(env_value "$1")"
    [[ -z "$value" ]] || placeholder "$1" "$value"
}

running() {
    [[ -n "$(compose ps --status running -q "$1" 2>/dev/null)" ]]
}

# ---------------------------------------------------------------------------
# 1. Tools
# ---------------------------------------------------------------------------
step "checking tools"
missing_tools=()
need() {   # need <label> <install command> <test command...>
    local label="$1" install="$2"
    shift 2
    if "$@" >/dev/null 2>&1; then
        echo "    ok: $label"
    else
        echo "    MISSING: $label  (install: $install)"
        missing_tools+=("$label")
    fi
}
deno_2() { [[ "$(deno --version 2>/dev/null | awk 'NR == 1 {print $2}')" == 2.* ]]; }
need docker "curl -fsSL https://get.docker.com | sh" command -v docker
need "docker compose" "curl -fsSL https://get.docker.com | sh" docker compose version
need "deno 2" "curl -fsSL https://deno.land/install.sh | sh" deno_2
need rclone "apt-get install -y rclone" command -v rclone
need git "apt-get install -y git" command -v git
need jq "apt-get install -y jq" command -v jq
need openssl "apt-get install -y openssl" command -v openssl
need curl "apt-get install -y curl" command -v curl
need python3 "apt-get install -y python3" command -v python3
need "python3 cryptography" "apt-get install -y python3-cryptography" python3 -c 'import cryptography'
if [[ ${#missing_tools[@]} -gt 0 ]]; then
    if [[ $dry_run -eq 1 ]]; then
        echo "    would: stop here until these are installed: ${missing_tools[*]}"
    else
        echo
        echo "Install the missing tools (docs/setup.md, section 2), then run: sudo $SELF" >&2
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# 2. .env
# ---------------------------------------------------------------------------
step ".env: $env_target"
echo "    $env_state"
if [[ "$env_state" == "exists" ]]; then
    mode="$(stat -c %a "$ENV_FILE" 2>/dev/null || stat -f %Lp "$ENV_FILE")"
    if [[ "$mode" != "600" ]]; then
        if [[ $dry_run -eq 1 ]]; then
            would "chmod 600 (it is $mode)"
        else
            chmod 600 "$ENV_FILE"
            echo "    mode was $mode; set to 600"
        fi
    fi
fi

if [[ $dry_run -eq 1 ]]; then
    for key in DOMAIN ACME_EMAIL ALLOWED_EMAIL GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET RCLONE_REMOTE; do
        if unset_value "$key"; then would "ask for $key"; else echo "    set: $key"; fi
    done
    for key in COUCHDB_PASSWORD JWT_SIGNING_KEY OAUTH_STORAGE_ENCRYPTION_KEY; do
        if unset_value "$key"; then would "generate $key"; else echo "    set: $key"; fi
    done
    if unset_value LIVESYNC_PASSPHRASE; then
        would "ask for LIVESYNC_PASSPHRASE (generate one, or type your own) and show it once"
    else
        echo "    set: LIVESYNC_PASSPHRASE"
    fi
else
    # Fail now, not inside a prompt loop, if there is nobody to ask.
    for key in DOMAIN ACME_EMAIL ALLOWED_EMAIL GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET \
            RCLONE_REMOTE LIVESYNC_PASSPHRASE; do
        if unset_value "$key" && ! { : </dev/tty; } 2>/dev/null; then
            echo "ERROR: $key is not set and there is no terminal to ask on. Run $SELF in a terminal." >&2
            exit 1
        fi
    done

    # Plain values. Each is asked until it looks right.
    if unset_value DOMAIN; then
        echo "    The base domain. CouchDB will be at couch.<domain>, the MCP server at mcp.<domain>."
        while :; do
            value="$(ask "Domain (for example notes.example.org)")"
            value="${value#https://}"; value="${value#http://}"; value="${value%/}"
            if [[ "$value" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] && ! placeholder DOMAIN "$value"; then
                break
            fi
            echo "    That does not look like a domain; try again."
        done
        set_env_value DOMAIN "$value"
    fi
    if unset_value ACME_EMAIL; then
        echo "    Let's Encrypt sends certificate expiry notices to this address."
        while value="$(ask "Email for Let's Encrypt")"; [[ ! "$value" =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]] || placeholder ACME_EMAIL "$value"; do
            echo "    That does not look like an email address; try again."
        done
        set_env_value ACME_EMAIL "$value"
    fi
    if unset_value ALLOWED_EMAIL; then
        echo "    The one Google account that may use the Claude connector."
        while value="$(ask "Your Google account email")"; [[ ! "$value" =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]] || placeholder ALLOWED_EMAIL "$value"; do
            echo "    That does not look like an email address; try again."
        done
        set_env_value ALLOWED_EMAIL "$value"
    fi

    if unset_value GOOGLE_CLIENT_ID || unset_value GOOGLE_CLIENT_SECRET; then
        cat <<EOF

    Create the Google OAuth client now (docs/setup.md, section 7):
    https://console.cloud.google.com/auth/overview -> Google Auth Platform

      1. Overview -> Get started: any app name, Audience: External, Create.
      2. Audience -> Test users -> Add users: $ALLOWED_EMAIL
      3. Clients -> Create client -> Web application, with this
         Authorized redirect URI, exactly:

           https://mcp.$DOMAIN/auth/callback

      4. Copy the client ID and secret. The Console may show the secret in
         full only once.

EOF
    fi
    if unset_value GOOGLE_CLIENT_ID; then
        while value="$(ask "Google client ID")"; [[ -z "$value" ]]; do :; done
        set_env_value GOOGLE_CLIENT_ID "$value"
    fi
    if unset_value GOOGLE_CLIENT_SECRET; then
        while value="$(ask_secret "Google client secret (hidden)")"; [[ -z "$value" ]]; do :; done
        set_env_value GOOGLE_CLIENT_SECRET "$value"
    fi
    if unset_value RCLONE_REMOTE; then
        default="$(sed -n 's/^RCLONE_REMOTE=//p' "$backend/.env.example")"
        value="$(ask "rclone remote for the nightly backup" "${default:-gdrive}")"
        set_env_value RCLONE_REMOTE "$value"
    fi

    # Random secrets. Generated only when empty: changing one later breaks
    # CouchDB logins, the connector or the stored OAuth clients.
    if unset_value COUCHDB_PASSWORD; then
        set_env_value COUCHDB_PASSWORD "$(openssl rand -base64 32)"
        echo "    generated COUCHDB_PASSWORD"
    fi
    if unset_value JWT_SIGNING_KEY; then
        set_env_value JWT_SIGNING_KEY "$(openssl rand -base64 48)"
        echo "    generated JWT_SIGNING_KEY"
    fi
    if unset_value OAUTH_STORAGE_ENCRYPTION_KEY; then
        set_env_value OAUTH_STORAGE_ENCRYPTION_KEY \
            "$(python3 -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')"
        echo "    generated OAUTH_STORAGE_ENCRYPTION_KEY"
    fi

    # The E2EE passphrase. Written to .env only after the user confirms it is
    # stored, so stopping here leaves nothing behind that nobody kept.
    if unset_value LIVESYNC_PASSPHRASE; then
        cat <<EOF

    LIVESYNC_PASSPHRASE is the end-to-end encryption key of every vault.
    Every device and the bridge need it, and nothing can recover the vaults
    without it.

EOF
        choice="$(ask "Generate one (g) or type your own (t)?" g)"
        if [[ "$choice" == [tT]* ]]; then
            while :; do
                first="$(ask_secret "Passphrase (hidden, at least 12 characters)")"
                if [[ ${#first} -lt 12 ]]; then
                    echo "    Too short; try again."
                    continue
                fi
                if [[ "$first" == *"'"* ]]; then
                    echo "    It must not contain a single quote; try again."
                    continue
                fi
                second="$(ask_secret "Same passphrase again")"
                [[ "$first" == "$second" ]] && break
                echo "    They differ; try again."
            done
            passphrase="$first"
            unset first second
            echo
            echo "    Store the passphrase you typed in a password manager now."
        else
            # Letters and digits only, so it is easy to type on a phone.
            passphrase="$(openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-32)"
            cat <<EOF

    Your passphrase, shown only this once:

        $passphrase

    Store it in a password manager now. Losing it loses the vaults.
EOF
        fi
        while [[ "$(ask "Type 'saved' once it is stored")" != "saved" ]]; do :; done
        set_env_value LIVESYNC_PASSPHRASE "$passphrase"
        unset passphrase
        echo "    LIVESYNC_PASSPHRASE written to .env. Clear your terminal scrollback if others can see it."
    fi
    echo "    all values set"
fi

# ---------------------------------------------------------------------------
# 3. DNS
# ---------------------------------------------------------------------------
# What to call the domain in messages; a dry run may not have a real one.
if unset_value DOMAIN; then shown_domain="<domain>"; else shown_domain="$DOMAIN"; fi
step "DNS: couch.$shown_domain and mcp.$shown_domain must point at this server"
if [[ $dry_run -eq 1 ]]; then
    would "check both names resolve to this server's public IPv4 address"
else
    public_ip=""
    for url in https://ifconfig.me https://api.ipify.org https://icanhazip.com; do
        public_ip="$(curl -4 -fsS --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]')" || public_ip=""
        [[ "$public_ip" =~ ^[0-9]+(\.[0-9]+){3}$ ]] && break
        public_ip=""
    done
    dns_ok=1
    if [[ -z "$public_ip" ]]; then
        echo "    WARN: could not detect this server's public IPv4 address."
        dns_ok=0
    fi
    for host in "couch.$DOMAIN" "mcp.$DOMAIN"; do
        addresses="$(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u | xargs || true)"
        if [[ -z "$addresses" ]]; then
            echo "    $host: does not resolve. Add an A record for it (docs/setup.md, section 1)."
            dns_ok=0
        elif [[ -n "$public_ip" && " $addresses " != *" $public_ip "* ]]; then
            echo "    $host: resolves to $addresses, but this server is $public_ip."
            dns_ok=0
        else
            echo "    $host: $addresses"
        fi
    done
    if [[ $dns_ok -eq 0 ]]; then
        echo "    Caddy cannot get certificates until both names point at this server."
        if ! ask_yes_no "    Continue anyway?"; then
            echo "Fix DNS, then run: sudo $SELF"
            exit 1
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 4. Folders
# ---------------------------------------------------------------------------
step "folders"
if [[ $dry_run -eq 1 ]]; then
    would "create $VAULT_ROOT (mode 755, owned by uid $VAULT_UID) and $GIT_ROOT (mode 700)"
    would "chown -R 5984:5984 couchdb/local.d (CouchDB's uid)"
else
    # Both containers run as VAULT_UID and must be able to write the mirror.
    make_vault_dir "$VAULT_ROOT"
    install -d -m 700 "$GIT_ROOT"
    echo "    $VAULT_ROOT and $GIT_ROOT ready"
    # CouchDB writes its docker.ini here and wants the folder as its own uid.
    if [[ $EUID -eq 0 ]]; then
        chown -R 5984:5984 "$BACKEND_DIR/couchdb/local.d"
        echo "    couchdb/local.d owned by uid 5984"
    fi
fi

# ---------------------------------------------------------------------------
# 5. CouchDB and Caddy
# ---------------------------------------------------------------------------
step "CouchDB and Caddy"
if [[ $dry_run -eq 1 ]]; then
    would "docker compose up -d couchdb caddy, then wait for https://couch.$shown_domain/_up"
else
    if running couchdb && running caddy; then
        echo "    already running"
    fi
    # A no-op for containers whose configuration has not changed.
    compose up -d couchdb caddy
    echo "    waiting for https://couch.$DOMAIN/_up (the first TLS certificate can take a minute)"
    up=0
    for _ in $(seq 1 40); do
        if couch GET _up --max-time 5 >/dev/null 2>&1; then
            up=1
            break
        fi
        sleep 3
    done
    if [[ $up -eq 0 ]]; then
        cat >&2 <<EOF
ERROR: https://couch.$DOMAIN/_up did not answer within two minutes.
  - Look at the certificate issuance: docker compose logs caddy
  - Check DNS (couch.$DOMAIN must point here) and that ports 80 and 443 are open.
  - Check CouchDB itself: docker compose logs couchdb
Then run: sudo $SELF
EOF
        exit 1
    fi
    echo "    CouchDB answers over TLS"
fi

# ---------------------------------------------------------------------------
# 6. Bridge config
# ---------------------------------------------------------------------------
step "bridge config"
config="$BACKEND_DIR/bridge/config.json"
if [[ -f "$config" ]]; then
    echo "    $config exists; left as it is"
elif [[ $dry_run -eq 1 ]]; then
    would "run ./scripts/gen-bridge-config.sh (the bridge is started later by add-vault.sh)"
else
    # Docker makes an empty directory here if the bridge ever started without
    # the file. It is safe to replace.
    if [[ -d "$config" ]]; then
        rmdir "$config" || {
            echo "ERROR: $config is a directory and not empty; move it away, then run: sudo $SELF" >&2
            exit 1
        }
    fi
    "$BACKEND_DIR/scripts/gen-bridge-config.sh"
fi

# ---------------------------------------------------------------------------
# 7. MCP server
# ---------------------------------------------------------------------------
mcp="https://mcp.$shown_domain"
step "MCP server at $mcp"
if [[ $dry_run -eq 1 ]]; then
    would "docker compose up -d --build mcp, then check the OAuth discovery endpoints"
else
    if running mcp; then
        echo "    already running; rebuilding only if the code changed"
    fi
    compose up -d --build mcp

    # The three requests claude.ai makes first. Retried while the server starts.
    mcp_checks() {
        local headers
        headers="$(curl -sS -o /dev/null -D - --max-time 10 "$mcp/mcp" 2>/dev/null)" || return 1
        [[ "$(head -n 1 <<< "$headers" | awk '{print $2}')" == "401" ]] || return 1
        grep -qi '^www-authenticate:.*resource_metadata' <<< "$headers" || return 1
        [[ "$(curl -fsS --max-time 10 "$mcp/.well-known/oauth-protected-resource/mcp" |
            jq -r '.resource // empty')" == "$mcp/mcp" ]] || return 1
        curl -fsS --max-time 10 "$mcp/.well-known/oauth-authorization-server" |
            jq -e '(.code_challenge_methods_supported | index("S256")) and .registration_endpoint' >/dev/null
    }
    ready=0
    for _ in $(seq 1 20); do
        if mcp_checks 2>/dev/null; then
            ready=1
            break
        fi
        sleep 3
    done
    if [[ $ready -eq 0 ]]; then
        cat >&2 <<EOF
ERROR: the MCP server's OAuth discovery is not right yet. Expected:
  - $mcp/mcp answers 401 with a www-authenticate header naming resource_metadata
  - $mcp/.well-known/oauth-protected-resource/mcp has "resource": "$mcp/mcp"
  - $mcp/.well-known/oauth-authorization-server lists S256 and a registration_endpoint
Look at: docker compose logs --tail=100 mcp   (docs/runbook.md)
Then run: sudo $SELF
EOF
        exit 1
    fi
    echo "    401 with resource_metadata, resource metadata and authorization server metadata are correct"
fi

# ---------------------------------------------------------------------------
# 8. Timers
# ---------------------------------------------------------------------------
step "timers"
timers_current() {
    local unit name
    for unit in "$BACKEND_DIR"/systemd/*; do
        name="$(basename "$unit")"
        cmp -s <(sed "s|@BACKEND_DIR@|$BACKEND_DIR|g" "$unit") "${SYSTEMD_DIR:-/etc/systemd/system}/$name" || return 1
    done
    for name in vault-git vault-backup vault-staleness; do
        systemctl is-enabled --quiet "$name.timer" 2>/dev/null || return 1
    done
}
if ! command -v systemctl >/dev/null 2>&1; then
    echo "    WARN: systemctl not found; install the timers on a systemd host with ./scripts/install-timers.sh"
elif timers_current; then
    echo "    already installed and enabled"
elif [[ $dry_run -eq 1 ]]; then
    would "run ./scripts/install-timers.sh"
else
    "$BACKEND_DIR/scripts/install-timers.sh"
fi

# ---------------------------------------------------------------------------
# 9. rclone remote
# ---------------------------------------------------------------------------
step "backup remote '${RCLONE_REMOTE:-}'"
if command -v rclone >/dev/null 2>&1 && rclone listremotes 2>/dev/null | grep -qxF "${RCLONE_REMOTE:-}:"; then
    echo "    configured"
else
    cat <<EOF
    Not configured yet. The nightly backup needs it (docs/setup.md, section 8):

      sudo rclone config        # new remote named '${RCLONE_REMOTE:-gdrive}', type "drive";
                                # use the headless flow and paste the token from
                                # a browser on your computer
      sudo rclone lsd ${RCLONE_REMOTE:-gdrive}:

    Everything else works without it; doctor.sh warns until it is set up.
EOF
fi

# ---------------------------------------------------------------------------
# 10. Health check and next steps
# ---------------------------------------------------------------------------
step "health check"
if [[ $dry_run -eq 1 ]]; then
    would "run ./scripts/doctor.sh"
    echo
    echo "Dry run: nothing was changed."
    exit 0
fi
doctor_ok=1
"$BACKEND_DIR/scripts/doctor.sh" || doctor_ok=0

echo
if [[ $doctor_ok -eq 0 ]]; then
    echo "Some checks failed (above). Fix them, then run: sudo ./scripts/doctor.sh"
    echo
fi
cat <<EOF
The backend is set up. Next:

  1. Add the connector in claude.ai: Customize -> Connectors -> + ->
     Add custom connector, with this URL:

       $mcp/mcp

  2. Add your first vault (docs/vaults.md):

       sudo ./scripts/add-vault.sh <name>
EOF
