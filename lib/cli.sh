#!/usr/bin/env bash
usage() {
    cat <<'EOF'
Usage: install-chatgpt.sh [OPTIONS]

AtomicGPT - install and update ChatGPT in your own folder.

Extract a ChatGPT RPM into ~/Programs/ChatGPT without changing the host OS.
Only newer RPM versions are installed unless --force is supplied.

  --target PATH, --install-dir PATH  Installation directory
  --latest                         Download the latest RPM (default)
  --rpm FILE_OR_HTTPS_URL           Use a specific package instead
  --config FILE                    Read a specific .env file
  --no-config                      Ignore the project's .env
  --check                          Compare versions without installing or closing
  --force                          Reinstall, downgrade, or adopt an untracked folder
  --if-running close|skip           Close ChatGPT or defer an update (default: close)
  --close-delay SECONDS             Warning delay before closing (default: 5)
  -y, --yes                        Consent to closing ChatGPT, including unattended
  --non-interactive                Never prompt; closing requires --yes
  --no-integrate                   Skip command/desktop/URI integration
  --keep-backup                    Retain the previous installation
  --version                        Print the installer version
  -h, --help                       Show this help

Value options also accept --name=value. Defaults < .env < environment < CLI.
ChatGPT is warned and closed ONLY when an installation will actually happen.
EOF
}
parse_args() {
    CHECK_ONLY=false FORCE=false ASSUME_YES=false NON_INTERACTIVE=false
    local option value
    while (( $# )); do
        option="$1"; value=''
        if [[ "$option" == --*=* ]]; then
            value="${option#*=}"; option="${option%%=*}"
            case "$option" in
                --target|--install-dir|--rpm|--config|--if-running|--close-delay) ;;
                *) die "$option does not accept a value" ;;
            esac
            set -- "$option" "$value" "${@:2}"
        fi
        case "$option" in
            --target|--install-dir|--rpm|--config|--if-running|--close-delay)
                [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "$option requires a value"
                case "$option" in
                    --target|--install-dir) INSTALL_DIR="$2" ;;
                    --rpm)
                        RPM_PATH="$2"; DOWNLOAD_LATEST=false
                        if [[ "$RPM_PATH" != *://* ]]; then RPM_PATH="$(realpath -m -- "$(expand_home "$RPM_PATH")")"; fi ;;
                    --if-running) IF_RUNNING="$2" ;;
                    --close-delay) CLOSE_DELAY="$2" ;;
                    --config) : ;;
                esac
                shift 2 ;;
            --latest) DOWNLOAD_LATEST=true; shift ;;
            --no-config) shift ;;
            --check) CHECK_ONLY=true; shift ;;
            --force) FORCE=true; shift ;;
            --yes|-y) ASSUME_YES=true; shift ;;
            --non-interactive) NON_INTERACTIVE=true; shift ;;
            --no-integrate) INTEGRATE_DESKTOP=false; shift ;;
            --keep-backup) KEEP_BACKUP=true; shift ;;
            --help|-h) usage; exit 0 ;;
            --version) printf 'AtomicGPT %s\n' "$ATOMICGPT_VERSION"; exit 0 ;;
            *) die "Unknown argument: $option (see --help)" ;;
        esac
    done
}
