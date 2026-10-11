#!/usr/bin/env bash
# Install the history, backup and staleness timers.
#
#   sudo ./scripts/install-timers.sh            install, reload, enable, start
#   ./scripts/install-timers.sh --dry-run       print the rendered units only
#
# The units in systemd/ are templates: @BACKEND_DIR@ stands for wherever this
# checkout lives, so the repo can be cloned anywhere. Re-run after moving the
# checkout or pulling unit changes; it overwrites the installed copies.
. "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
TIMERS=(vault-git.timer vault-backup.timer vault-staleness.timer)

dry_run=0
case "${1:-}" in
    "") ;;
    --dry-run) dry_run=1 ;;
    *) echo "Usage: sudo $0 [--dry-run]" >&2; exit 2 ;;
esac

# The path goes unquoted into ExecStart and into a sed replacement, so it must
# not contain whitespace or the sed delimiter.
if [[ "$BACKEND_DIR" =~ [[:space:]\|] ]]; then
    echo "ERROR: move the checkout to a path without spaces or '|': $BACKEND_DIR" >&2
    exit 1
fi

render() {
    sed "s|@BACKEND_DIR@|$BACKEND_DIR|g" "$1"
}

if [[ $dry_run -eq 1 ]]; then
    for unit in "$BACKEND_DIR"/systemd/*; do
        echo "# ---- $(basename "$unit")"
        render "$unit"
    done
    exit 0
fi

require_root

for unit in "$BACKEND_DIR"/systemd/*; do
    render "$unit" > "$SYSTEMD_DIR/$(basename "$unit")"
    chmod 644 "$SYSTEMD_DIR/$(basename "$unit")"
    echo "==> installed $SYSTEMD_DIR/$(basename "$unit")"
done

systemctl daemon-reload
systemd-analyze verify "$SYSTEMD_DIR"/vault-*.service
systemctl enable --now "${TIMERS[@]}"
systemctl list-timers 'vault-*'
