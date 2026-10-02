#!/usr/bin/env bash
SETUP_TEMP='' SETUP_COLOR=false

setup_usage() {
    cat <<'EOF'
Usage: setup-wizard.sh [--output FILE] [--no-color]

Walk through installation settings and generate a literal .env configuration.
Existing settings are used as defaults. Review and confirm before saving.
The final question offers to open the automatic-update wizard.

  --output FILE  Configuration destination (default: .env beside this script)
  --no-color     Disable terminal colors and screen clearing
  -h, --help     Show this help

The wizard does not download or install ChatGPT. Ctrl+C cancels; an existing
configuration is backed up before replacement. No TUI packages are required.
EOF
}
setup_cleanup() {
    if [[ -n "$SETUP_TEMP" && -f "$SETUP_TEMP" ]]; then rm -f -- "$SETUP_TEMP"; fi
    if [[ "$SETUP_COLOR" == true ]]; then printf '\033[0m'; fi
}
setup_screen() {
    local step="$1" title="$2"
    if [[ "$SETUP_COLOR" == true ]]; then
        printf '\033[H\033[2J\033[1;36m'
    fi
    printf '\n  +------------------------------------------------------------------+\n'
    printf '  |  ChatGPT installer  /  Guided setup                               |\n'
    printf '  +------------------------------------------------------------------+\n'
    if [[ "$SETUP_COLOR" == true ]]; then printf '\033[0m\033[1m'; fi
    printf '\n  Step %s of 7  -  %s\n\n' "$step" "$title"
    if [[ "$SETUP_COLOR" == true ]]; then printf '\033[0m'; fi
}
setup_text() { printf '  %s\n' "$@"; printf '\n'; }
setup_read() {
    local destination="$1" question="$2" default="$3" setup_reply
    printf '  %s' "$question"
    [[ -z "$default" ]] || printf ' [%s]' "$default"
    printf ': '
    if [[ -t 0 ]]; then
        IFS= read -r -e setup_reply || { info 'Setup cancelled; input ended.'; exit 0; }
    else
        IFS= read -r setup_reply || { info 'Setup cancelled; input ended.'; exit 0; }
    fi
    printf -v "$destination" '%s' "${setup_reply:-$default}"
}
setup_choice() {
    local destination="$1" first="$2" second="$3" default="$4" setup_selected
    printf '  1) %s\n  2) %s\n\n' "$first" "$second"
    while true; do
        setup_read setup_selected 'Choose 1 or 2' "$default"
        case "$setup_selected" in
            1|2) printf -v "$destination" '%s' "$setup_selected"; return 0 ;;
            *) warn 'Please enter 1 or 2, or press Enter to accept the default.' ;;
        esac
    done
}
setup_location() {
    setup_screen 1 'Installation location'
    setup_text 'Choose a folder used only for ChatGPT, such as ~/Programs/ChatGPT.' \
        'Updates replace this folder. Your application profile stays separate.' \
        'No root access or changes to the host operating system are needed.'
    local validation
    while true; do
        setup_read INSTALL_DIR 'Install ChatGPT in' "$INSTALL_DIR"
        TARGET="$(expand_home "$INSTALL_DIR")"
        if validation="$(valid_line "$TARGET"; validate_target_path 2>&1)"; then
            INSTALL_DIR="$(realpath -m -- "$TARGET")"
            return 0
        fi
        warn "$validation"
    done
}
setup_downloads() {
    setup_screen 2 'Downloads on future runs'
    setup_text 'Enable downloads to check the latest RPM whenever you run the installer.' \
        'It installs only a newer version; unchanged downloads are cached.' \
        'This does not create a background schedule. Scheduling comes at the end.'
    local selected default=1 path
    [[ "$DOWNLOAD_LATEST" == true ]] || default=2
    setup_choice selected 'Yes, automatically download the latest RPM' 'No, use an RPM file I provide' "$default"
    if [[ "$selected" == 1 ]]; then
        DOWNLOAD_LATEST=true RPM_PATH=''
        return 0
    fi
    DOWNLOAD_LATEST=false
    setup_text 'Provide a readable RPM file. For later updates, replace that file' \
        'with a newer RPM or run the installer with --rpm /path/to/new.rpm.'
    path="$(expand_home "$RPM_PATH")"
    if [[ -n "$path" && "$path" != /* && -n "$CONFIG_FILE" ]]; then
        path="$(dirname -- "$CONFIG_FILE")/$path"
    fi
    while true; do
        setup_read path 'Local RPM path' "$path"
        path="$(expand_home "$path")"
        if [[ -n "$path" && "$path" != *$'\r'* && "$path" != *$'\n'* && -f "$path" && -r "$path" ]]; then
            RPM_PATH="$(realpath -- "$path")"
            return 0
        fi
        warn 'Choose an existing, readable RPM file.'
    done
}
setup_desktop() {
    setup_screen 3 'Desktop integration'
    setup_text 'Create a ChatGPT launcher in your application menu and a chatgpt command.' \
        'Also register codex:// links when your desktop supports URI handlers.' \
        'An existing regular file at ~/.local/bin/chatgpt is preserved.'
    local selected default=1
    [[ "$INTEGRATE_DESKTOP" == true ]] || default=2
    setup_choice selected 'Enable desktop and command integration' 'Install the application files only' "$default"
    if [[ "$selected" == 1 ]]; then INTEGRATE_DESKTOP=true; else INTEGRATE_DESKTOP=false; fi
}
setup_closing() {
    setup_screen 4 'When ChatGPT is running'
    setup_text 'Updates stage and validate the package before touching the application.' \
        'Closing ChatGPT can discard unsaved input. Interactive runs ask first;' \
        'unattended closing needs advance consent from --yes or the update wizard.'
    local selected default=1
    [[ "$IF_RUNNING" == skip ]] || default=2
    setup_choice selected 'Wait: skip the update until ChatGPT is closed' 'Warn and ask to close ChatGPT for the update' "$default"
    if [[ "$selected" == 1 ]]; then IF_RUNNING=skip; return 0; fi
    IF_RUNNING=close
    setup_text 'A terminal warning and optional desktop notification precede shutdown.' \
        'Choose how long the user has to save their work (0 through 60 seconds).'
    while true; do
        setup_read CLOSE_DELAY 'Warning delay in seconds' "$CLOSE_DELAY"
        if [[ "$CLOSE_DELAY" =~ ^[0-9]+$ && ${#CLOSE_DELAY} -le 2 ]] && (( 10#$CLOSE_DELAY <= 60 )); then
            CLOSE_DELAY=$((10#$CLOSE_DELAY)); return 0
        fi
        warn 'Enter a whole number from 0 through 60.'
    done
}
setup_backups() {
    setup_screen 5 'Previous-version backups'
    setup_text 'A temporary backup is always used so replacement failures can roll back.' \
        'You can also keep each previous application folder after a successful update.' \
        'Kept backups use additional disk space; remove them manually when unneeded.'
    local selected default=2
    [[ "$KEEP_BACKUP" == true ]] && default=1
    setup_choice selected 'Keep the previous version after successful updates' 'Remove the temporary backup after successful updates' "$default"
    if [[ "$selected" == 1 ]]; then KEEP_BACKUP=true; else KEEP_BACKUP=false; fi
}
setup_write_config() {
    local parent backup
    parent="$(dirname -- "$SETUP_OUTPUT")"
    mkdir -p -- "$parent"
    [[ ! -L "$SETUP_OUTPUT" && ( ! -e "$SETUP_OUTPUT" || -f "$SETUP_OUTPUT" ) ]] || die 'Configuration destination must be a regular file, not a symlink.'
    SETUP_TEMP="$(mktemp "$parent/.chatgpt-env.XXXXXX")"
    {
        printf '# Generated by setup-wizard.sh. CLI options override these settings.\n'
        printf '# Location: this application folder is replaced during updates.\nINSTALL_DIR="%s"\n\n' "$INSTALL_DIR"
        printf '# Downloads happen when the installer runs; scheduling is separate.\n'
        printf 'DOWNLOAD_LATEST=%s\nRPM_PATH="%s"\nRPM_URL="%s"\n\n' "$DOWNLOAD_LATEST" "$RPM_PATH" "$RPM_URL"
        printf 'INTEGRATE_DESKTOP=%s\nKEEP_BACKUP=%s\n\n' "$INTEGRATE_DESKTOP" "$KEEP_BACKUP"
        printf '# close still needs interactive permission or --yes; skip defers.\n'
        printf 'IF_RUNNING=%s\nCLOSE_DELAY=%s\n' "$IF_RUNNING" "$CLOSE_DELAY"
    } > "$SETUP_TEMP"
    # mktemp creates a private file; a backup also has mode 600.
    if [[ -f "$SETUP_OUTPUT" ]]; then
        backup="$(mktemp "$SETUP_OUTPUT.backup.$(date '+%Y%m%d-%H%M%S').XXXXXX")"
        cp -- "$SETUP_OUTPUT" "$backup"
        info "Previous configuration backed up: $backup"
    fi
    mv -f -- "$SETUP_TEMP" "$SETUP_OUTPUT"
    SETUP_TEMP=''
    success "Configuration saved: $SETUP_OUTPUT"
}
setup_review() {
    setup_screen 6 'Review your settings'
    printf '  Installation:  %s\n' "$INSTALL_DIR"
    if [[ "$DOWNLOAD_LATEST" == true ]]; then
        printf '  Downloads:     latest RPM on each run\n  RPM source:    %s\n' "$RPM_URL"
    else
        printf '  Downloads:     disabled\n  Local RPM:     %s\n' "$RPM_PATH"
    fi
    printf '  Integration:   %s\n  Keep backups:  %s\n  If running:    %s\n  Warning delay: %s seconds\n' \
        "$INTEGRATE_DESKTOP" "$KEEP_BACKUP" "$IF_RUNNING" "$CLOSE_DELAY"
    printf '  Save to:       %s\n\n' "$SETUP_OUTPUT"
    if [[ -f "$SETUP_OUTPUT" ]]; then setup_text 'Your existing configuration will be backed up before it is replaced.'; fi
    setup_text 'Saving settings does not download or install ChatGPT.'
    local selected
    setup_choice selected 'Save these settings' 'Cancel without saving' 1
    if [[ "$selected" == 2 ]]; then info 'Setup cancelled; configuration unchanged.'; return 1; fi
}
setup_finish() {
    setup_screen 7 'Automatic update scheduling'
    setup_text 'Your configuration is saved. Schedule automatic checks with a systemd' \
        'user timer, choosing daily or weekly checks and how running apps are handled.' \
        'You can change or completely remove that schedule later.'
    local selected
    setup_choice selected 'Open the automatic-update wizard now' 'Finish setup; I will run updates myself' 2
    printf '\n'
    success "Configuration ready: $SETUP_OUTPUT"
    printf 'Next install/update command:\n  %q --config %q\n' "$SCRIPT_DIR/install-chatgpt.sh" "$SETUP_OUTPUT"
    if [[ -d "$TARGET" && ! -f "$TARGET/.chatgpt-install-info" ]]; then
        warn 'This installation has no version record. Add --force --keep-backup for its first managed installation.'
    fi
    if [[ "$selected" == 1 ]]; then
        if ! (unset "${CONFIG_KEYS[@]}"; bash "$SCRIPT_DIR/autoupdate-wizard.sh" --config "$SETUP_OUTPUT"); then
            warn 'Your .env is saved, but automatic-update setup did not complete.'
            printf 'Retry:\n  %q --config %q\n' "$SCRIPT_DIR/autoupdate-wizard.sh" "$SETUP_OUTPUT"
            return 1
        fi
    else
        info 'No automatic-update schedule was changed.'
    fi
}
setup_main() {
    SETUP_OUTPUT="$SCRIPT_DIR/.env"
    local no_color=false
    while (( $# )); do
        case "$1" in
            --help|-h) setup_usage; return 0 ;;
            --output)
                [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die '--output requires a file'
                SETUP_OUTPUT="$2"; shift 2 ;;
            --output=*) SETUP_OUTPUT="${1#*=}"; [[ -n "$SETUP_OUTPUT" ]] || die '--output requires a file'; shift ;;
            --no-color) no_color=true; shift ;;
            *) die "Unknown argument: $1 (see --help)" ;;
        esac
    done
    require_command realpath
    [[ -n "$SETUP_OUTPUT" ]] || die 'Configuration destination cannot be empty.'
    SETUP_OUTPUT="$(expand_home "$SETUP_OUTPUT")"
    [[ ! -L "$SETUP_OUTPUT" ]] || die 'Configuration destination must not be a symlink.'
    SETUP_OUTPUT="$(realpath -m -- "$SETUP_OUTPUT")"
    [[ ! -e "$SETUP_OUTPUT" || -f "$SETUP_OUTPUT" ]] || die 'Configuration destination must be a file.'
    if [[ -t 1 && "${TERM:-dumb}" != dumb && "$no_color" == false && ! -v NO_COLOR ]]; then SETUP_COLOR=true; fi
    trap setup_cleanup EXIT
    trap 'info "Setup cancelled."; exit 130' INT
    trap 'exit 143' TERM
    if [[ -f "$SETUP_OUTPUT" ]]; then load_config --config "$SETUP_OUTPUT"; else load_config --no-config; fi
    setup_location
    setup_downloads
    setup_desktop
    setup_closing
    setup_backups
    validate_config
    validate_target_path
    if ! setup_review; then return 0; fi
    setup_write_config
    setup_finish
}
