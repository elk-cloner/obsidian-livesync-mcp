#!/usr/bin/env bash
# Alert when the plain-file mirror stops updating.
#
# If the bridge dies, devices keep syncing to each other through CouchDB and
# nothing looks wrong -- but git history, the backup and Claude's view all go
# quietly stale. This is the check that catches that.
#
# Exit: 0 all fresh, 1 something stale, 2 something missing.
. "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

MAX_AGE_HOURS="${MAX_AGE_HOURS:-24}"
status=0

for vault in $(vault_list); do
    work="$VAULT_ROOT/$vault"

    if [[ ! -d "$work" ]]; then
        echo "CRITICAL $vault: $work is missing"
        status=2
        continue
    fi

    if ! find "$work" -type f -name '*.md' -print -quit | grep -q .; then
        echo "WARN $vault: no markdown files in the mirror"
        (( status < 1 )) && status=1
        continue
    fi

    # "Is anything newer than the threshold?" avoids GNU-only -printf and the
    # GNU/BSD split in stat(1).
    if find "$work" -type f -name '*.md' \
            -newermt "-${MAX_AGE_HOURS} hours" -print -quit | grep -q .; then
        echo "OK $vault: updated within ${MAX_AGE_HOURS}h"
    else
        echo "WARN $vault: nothing modified in ${MAX_AGE_HOURS}h -- is the bridge running?"
        (( status < 1 )) && status=1
    fi
done

exit $status
