#!/usr/bin/env bash
# AtomicGPT guided setup, using Bash and the installer's existing utilities.
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
for module in common config setup; do
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/lib/$module.sh"
done
setup_main "$@"
