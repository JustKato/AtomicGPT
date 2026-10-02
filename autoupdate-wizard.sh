#!/usr/bin/env bash
# Manage one per-user systemd schedule; never requires root.
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
for module in common config scheduler; do
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/lib/$module.sh"
done
wizard_main "$@"
