#!/usr/bin/env bash
# User-space ChatGPT RPM installer. Keep this entry point small.
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
for module in common config cli version package processes desktop logging install; do
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/lib/$module.sh"
done
main "$@"
