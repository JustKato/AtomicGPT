#!/usr/bin/env bash
# Shared logging and literal path handling (never evaluate configuration).
ATOMICGPT_VERSION=2.0.0
info() { printf '[INFO] %s\n' "$*"; }
success() { printf '[ OK ] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { warn "$*"; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }
require_command() { command_exists "$1" || die "Required command not found: $1"; }
trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}
expand_home() {
    local value="$1"
    # Configuration contains a literal tilde; this function expands it.
    # shellcheck disable=SC2088
    case "$value" in
        '~') value="$HOME" ;;
        '~/'*) value="$HOME/${value:2}" ;;
        '$HOME'*) value="$HOME${value:5}" ;;
        '${HOME}'*) value="$HOME${value:7}" ;;
    esac
    printf '%s' "$value"
}
valid_line() {
    [[ "$1" != *$'\n'* && "$1" != *$'\r'* ]] || die 'Values cannot contain newlines.'
}
confirm() {
    local answer
    [[ "${ASSUME_YES:-false}" == true ]] && return 0
    [[ "${NON_INTERACTIVE:-false}" == false && -t 0 ]] || return 1
    read -r -p "$1 [y/N] " answer || return 1
    [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]]
}
notify_user() {
    if command_exists notify-send; then
        notify-send --app-name=AtomicGPT 'ChatGPT update' "$1" >/dev/null 2>&1 || true
    fi
}
validate_target_path() {
    [[ ! -L "$TARGET" ]] || die 'The installation target must not be a symlink.'
    TARGET="$(realpath -m -- "$TARGET")"
    local protected canonical
    for protected in / /usr /usr/local /etc /var /opt /home /tmp /bin /sbin /lib /lib64 "$HOME" "$HOME/Programs" "$HOME/.local" "$SCRIPT_DIR"; do
        canonical="$(realpath -m -- "$protected")"
        [[ "$TARGET" != "$canonical" ]] || die "Refusing unsafe installation target: $TARGET"
    done
    [[ "$SCRIPT_DIR/" != "$TARGET/"* && "$(realpath -m -- "$HOME")/" != "$TARGET/"* ]] || die 'Target cannot contain this project or your home directory.'
    [[ ! -e "$TARGET" || -d "$TARGET" ]] || die 'Target exists and is not a directory.'
}
