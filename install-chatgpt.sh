#!/usr/bin/env bash
# AtomicGPT: install and update ChatGPT from an RPM in user space.
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
for module in common config cli version package processes desktop logging install; do
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/lib/$module.sh"
done
main "$@"
