#!/usr/bin/env bash
# Put the knowledge vault schema into a connected vault.
#
#   sudo ./scripts/seed-vault.sh <name>              first seed of a vault
#   sudo ./scripts/seed-vault.sh <name> --upgrade    refresh the schema files
#
# Run it after add-vault.sh has connected the vault. It copies vault/template
# from this repo into $VAULT_ROOT/<name>; the bridge then pushes the files to
# CouchDB and every device pulls them on its next sync. The examples in
# vault/examples are never copied.
#
# The first seed refuses to overwrite anything: if any template file already
# exists in the vault, it stops and lists them.
#
# --upgrade replaces only the files this repo owns: the root CLAUDE.md,
# _templates/ and _bases/. It never touches areas, log.md, README.md or
# _state/. It commits history before and after, so the previous files are one
# `git checkout` away.
#
# .obsidian/ is not copied: device config does not sync (docs/runbook.md), so
# each device sets the two template options itself (vault/README.md).
. "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

usage() {
    echo "Usage: sudo $0 <vault-name> [--upgrade]" >&2
    exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage
name="$1"
mode="seed"
if [[ $# -eq 2 ]]; then
    [[ "$2" == "--upgrade" ]] || usage
    mode="upgrade"
fi

if ! valid_vault_name "$name"; then
    echo "ERROR: invalid vault name '$name'." >&2
    exit 1
fi
require_root

TEMPLATE="$REPO_ROOT/vault/template"
work="$VAULT_ROOT/$name"

if [[ ! -f "$TEMPLATE/CLAUDE.md" ]]; then
    echo "ERROR: no schema template at $TEMPLATE" >&2
    exit 1
fi
if ! vault_configured "$name" || [[ ! -d "$work" ]]; then
    echo "ERROR: '$name' is not a connected vault. Add it first: sudo ./scripts/add-vault.sh $name" >&2
    exit 1
fi

schema_version() {
    sed -n 's/^Schema version: *//p' "$1" | head -n 1
}

# Template files to copy, relative to the template root, for the given mode.
template_files() {
    (
        cd "$TEMPLATE"
        if [[ "$mode" == "seed" ]]; then
            find . -path ./.obsidian -prune -o -type f -print
        else
            printf '%s\n' ./CLAUDE.md
            find ./_templates ./_bases -type f
        fi
    ) | sed 's|^\./||' | LC_ALL=C sort
}

# Copy one file into the vault the way the MCP server writes: stage it under a
# dot-prefixed name in the target folder (hidden files are outside the bridge's
# sync scope), then rename. The bridge never sees a half-written note.
place() {
    local rel="$1" src="$TEMPLATE/$1" dest="$work/$1" dir staged
    dir="$(dirname -- "$dest")"
    install -d -m 755 "$dir"
    staged="$(mktemp "$dir/.seed-vault-XXXXXX")"
    cat "$src" > "$staged"
    chmod 644 "$staged"
    mv -f "$staged" "$dest"
}

files="$(template_files)"

if [[ "$mode" == "seed" ]]; then
    if [[ -e "$work/CLAUDE.md" ]]; then
        echo "ERROR: $work already has a CLAUDE.md. To refresh the schema files, run:" >&2
        echo "  sudo $0 $name --upgrade" >&2
        exit 1
    fi
    conflicts=()
    while IFS= read -r rel; do
        [[ -e "$work/$rel" ]] && conflicts+=("$rel")
    done <<< "$files"
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        echo "ERROR: these template files already exist in $work; move them away first:" >&2
        printf '  %s\n' "${conflicts[@]}" >&2
        exit 1
    fi

    history_repo_init "$name"
    while IFS= read -r rel; do
        place "$rel"
    done <<< "$files"

    # The first log line records when the vault was seeded, in UTC like every
    # other time in the vault.
    now="$(date -u '+%Y-%m-%d %H:%M')"
    python3 - "$work/log.md" "$now" <<'PY'
import sys
path, now = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read().replace("YYYY-MM-DD HH:MM | seed-vault", f"{now} | seed-vault", 1)
open(path, "w", encoding="utf-8").write(text)
PY

    count="$(wc -l <<< "$files" | tr -d ' ')"
    echo "==> seeded $work with $count file(s), schema version $(schema_version "$TEMPLATE/CLAUDE.md")"
else
    if [[ ! -f "$work/CLAUDE.md" ]]; then
        echo "ERROR: $work has no CLAUDE.md yet; seed it first: sudo $0 $name" >&2
        exit 1
    fi
    old_version="$(schema_version "$work/CLAUDE.md")"
    new_version="$(schema_version "$TEMPLATE/CLAUDE.md")"

    history_repo_init "$name"
    history_commit "$name"   # snapshot of the current state, for undo

    changed=0
    while IFS= read -r rel; do
        if [[ -f "$work/$rel" ]] && cmp -s "$TEMPLATE/$rel" "$work/$rel"; then
            continue
        fi
        place "$rel"
        echo "    updated $rel"
        changed=$((changed + 1))
    done <<< "$files"
    echo "==> $changed file(s) updated; schema version ${old_version:-unknown} -> ${new_version:-unknown}"
    if [[ $changed -gt 0 ]]; then
        echo "    Files removed from the template are left in place; delete them by hand if unused."
    fi
fi

own_by_vault_uid -R "$work"
history_commit "$name"
if github_enabled; then
    history_push "$name"
fi

cat <<EOF

Devices receive the schema files on their next sync. In Obsidian, set the
template folder and the attachment folder on each device (vault/README.md).
EOF
