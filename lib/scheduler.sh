#!/usr/bin/env bash
UNIT_NAME=chatgpt-autoupdate
MANAGED_MARKER='# Managed by ChatGPT RPM installer'

wizard_usage() {
    cat <<'EOF'
Usage: autoupdate-wizard.sh [--config FILE | --no-config] [--status | --remove]

No action option: ask questions and set up or replace a user systemd timer.
  --config FILE  Use an existing .env as defaults for the questions
  --no-config    Ignore the project's .env
  --status       Show schedule configuration, timer status and log command
  --remove       Disable/remove the managed timer, service, runner and config
  -h, --help     Show this help

Only one managed schedule is supported per user. Removal leaves ChatGPT and
the project's .env installed. All scheduling changes run as your own user.
EOF
}
scheduler_paths() {
    UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    UPDATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/chatgpt-rpm-installer"
    SERVICE_FILE="$UNIT_DIR/$UNIT_NAME.service"
    TIMER_FILE="$UNIT_DIR/$UNIT_NAME.timer"
    RUNNER_FILE="$UPDATE_DIR/run-update.sh"
    UPDATE_CONFIG="$UPDATE_DIR/update.env"
}
owned_file() {
    [[ -f "$1" ]] && [[ "$(head -n 1 -- "$1")" == "$MANAGED_MARKER" ]]
}
guard_managed_files() {
    local file
    for file in "$SERVICE_FILE" "$TIMER_FILE" "$RUNNER_FILE" "$UPDATE_CONFIG"; do
        if [[ -L "$file" || ( -e "$file" && ! -f "$file" ) ]]; then die "Refusing to replace/remove special file: $file"; fi
        if [[ -e "$file" ]] && ! owned_file "$file"; then die "Refusing to replace/remove unmanaged file: $file"; fi
    done
}
schedule_status() {
    if [[ -f "$TIMER_FILE" ]]; then
        cat -- "$TIMER_FILE"
        printf '\nUpdater configuration: %s\n' "$UPDATE_CONFIG"
        systemctl --user list-timers --all "$UNIT_NAME.timer" || return 1
        printf '\nLogs: journalctl --user -u %s.service\n' "$UNIT_NAME"
    else
        info 'No automatic updates configured by this wizard.'
    fi
}
remove_schedule() {
    guard_managed_files
    local file found=false
    for file in "$SERVICE_FILE" "$TIMER_FILE" "$RUNNER_FILE" "$UPDATE_CONFIG"; do
        if [[ -e "$file" ]]; then found=true; fi
    done
    if [[ "$found" == false ]]; then info 'No managed automatic updates to remove.'; return 0; fi
    # If the user manager is unavailable, don't claim the schedule was removed.
    systemctl --user show-environment >/dev/null || die 'Cannot reach the user systemd manager. Run this from your login session.'
    if [[ -f "$TIMER_FILE" ]]; then
        systemctl --user disable --now "$UNIT_NAME.timer"
        systemctl --user clean --what=state "$UNIT_NAME.timer" || die 'Timer disabled, but timestamp cleanup failed. Resolve the error and rerun --remove.'
    fi
    if [[ -f "$SERVICE_FILE" ]]; then systemctl --user stop "$UNIT_NAME.service"; fi
    for file in "$SERVICE_FILE" "$TIMER_FILE" "$RUNNER_FILE" "$UPDATE_CONFIG"; do
        if owned_file "$file"; then rm -f -- "$file"; fi
    done
    rmdir -- "$UPDATE_DIR" 2>/dev/null || true
    systemctl --user daemon-reload
    systemctl --user reset-failed "$UNIT_NAME.service" "$UNIT_NAME.timer" >/dev/null 2>&1 || true
    success 'Automatic updates removed. ChatGPT remains installed.'
}
ask() {
    local destination="$1" question="$2" default="$3" prompt_reply
    read -r -p "$question [$default]: " prompt_reply || die 'Input ended; no schedule was created.'
    printf -v "$destination" '%s' "${prompt_reply:-$default}"
}
systemd_quote() {
    local value="$1"
    value="${value//\\/\\\\}"; value="${value//\"/\\\"}"
    value="${value//%/%%}"; value="${value//\$/\$\$}"
    printf '"%s"' "$value"
}
write_schedule() {
    local temp bash_binary
    bash_binary="$(command -v bash)"
    mkdir -p -- "$UNIT_DIR" "$UPDATE_DIR"
    chmod 700 "$UPDATE_DIR"
    # Generated config is a literal snapshot. The project .env is untouched.
    temp="$(mktemp "$UPDATE_DIR/.config.XXXXXX")"
    {
        printf '%s\n' "$MANAGED_MARKER"
        printf 'INSTALL_DIR="%s"\nDOWNLOAD_LATEST=%s\nRPM_PATH="%s"\nRPM_URL="%s"\n' "$TARGET" "$DOWNLOAD_LATEST" "$RPM_SOURCE_LOCAL" "$RPM_URL"
        printf 'INTEGRATE_DESKTOP=%s\nKEEP_BACKUP=%s\nIF_RUNNING=%s\nCLOSE_DELAY=%s\n' "$INTEGRATE_DESKTOP" "$KEEP_BACKUP" "$IF_RUNNING" "$CLOSE_DELAY"
    } > "$temp"
    mv -f -- "$temp" "$UPDATE_CONFIG"
    temp="$(mktemp "$UPDATE_DIR/.runner.XXXXXX")"
    {
        printf '%s\nset -Eeuo pipefail\n' "$MANAGED_MARKER"
        # Capture paths needed on desktops with tools outside /usr/bin.
        printf 'export PATH=%q\n' "$PATH"
        printf 'export XDG_DATA_HOME=%q\n' "${XDG_DATA_HOME:-$HOME/.local/share}"
        printf 'unset'; printf ' %s' "${CONFIG_KEYS[@]}"; printf '\n'
        printf 'exec %q %q --config %q --non-interactive' "$bash_binary" "$SCRIPT_DIR/install-chatgpt.sh" "$UPDATE_CONFIG"
        if [[ "$IF_RUNNING" == close ]]; then printf ' --yes'; fi
        printf '\n'
    } > "$temp"
    chmod 700 "$temp"
    mv -f -- "$temp" "$RUNNER_FILE"
    temp="$(mktemp "$UNIT_DIR/.service.XXXXXX")"
    cat > "$temp" <<EOF
$MANAGED_MARKER
[Unit]
Description=Update the user-space ChatGPT installation

[Service]
Type=oneshot
ExecStart=$(systemd_quote "$bash_binary") $(systemd_quote "$RUNNER_FILE")
TimeoutStartSec=45min
EOF
    chmod 644 "$temp"
    mv -f -- "$temp" "$SERVICE_FILE"
    temp="$(mktemp "$UNIT_DIR/.timer.XXXXXX")"
    cat > "$temp" <<EOF
$MANAGED_MARKER
[Unit]
Description=Check for ChatGPT updates on a schedule

[Timer]
OnCalendar=$CALENDAR
Persistent=true
RandomizedDelaySec=5min
Unit=$UNIT_NAME.service

[Install]
WantedBy=timers.target
EOF
    chmod 644 "$temp"
    mv -f -- "$temp" "$TIMER_FILE"
    systemctl --user daemon-reload
    systemctl --user enable "$UNIT_NAME.timer"
    # restart also applies a changed schedule to an already active timer.
    systemctl --user restart "$UNIT_NAME.timer"
    success 'Automatic updates enabled.'
    info "Configuration snapshot: $UPDATE_CONFIG"
    info "Status: $SCRIPT_DIR/autoupdate-wizard.sh --status"
    info "Remove: $SCRIPT_DIR/autoupdate-wizard.sh --remove"
    info "Logs: journalctl --user -u $UNIT_NAME.service"
}
setup_schedule() {
    systemctl --user show-environment >/dev/null || die 'Cannot reach the user systemd manager. Run this from your login session.'
    guard_managed_files
    load_config "$@"
    validate_config
    info 'Configure automatic updates (one user-level systemd timer).'
    local answer frequency update_time weekday confirmation
    ask TARGET 'Installation directory' "$TARGET"
    TARGET="$(expand_home "$TARGET")"
    valid_line "$TARGET"
    validate_target_path
    ask answer 'Package source: latest or local' "$(if [[ "$DOWNLOAD_LATEST" == true ]]; then printf latest; else printf local; fi)"
    RPM_SOURCE_LOCAL=''
    case "$answer" in
        latest) DOWNLOAD_LATEST=true ;;
        local)
            DOWNLOAD_LATEST=false
            ask RPM_SOURCE_LOCAL 'Path to RPM (replace this file when a new RPM is available)' "$RPM_SOURCE"
            RPM_SOURCE_LOCAL="$(realpath -m -- "$(expand_home "$RPM_SOURCE_LOCAL")")"
            [[ -r "$RPM_SOURCE_LOCAL" && -f "$RPM_SOURCE_LOCAL" ]] || die 'The selected local RPM does not exist or cannot be read.' ;;
        *) die 'Package source must be latest or local.' ;;
    esac
    valid_line "$RPM_SOURCE_LOCAL"
    ask frequency 'Check daily or weekly' daily
    ask update_time 'Time in your system timezone (HH:MM)' '09:00'
    [[ "$update_time" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || die 'Enter a time from 00:00 to 23:59.'
    case "$frequency" in
        daily) CALENDAR="*-*-* $update_time:00" ;;
        weekly)
            ask weekday 'Day (Mon Tue Wed Thu Fri Sat Sun)' Mon
            case "$weekday" in Mon|Tue|Wed|Thu|Fri|Sat|Sun) ;; *) die 'Invalid weekday.' ;; esac
            CALENDAR="$weekday *-*-* $update_time:00" ;;
        *) die 'Frequency must be daily or weekly.' ;;
    esac
    warn 'Closing ChatGPT for an update can discard unsaved input.'
    ask IF_RUNNING 'If ChatGPT is running: skip or close (close gives advance consent)' skip
    case "$IF_RUNNING" in skip|close) ;; *) die 'Choose skip or close.' ;; esac
    ask answer 'Keep the previous installation as a backup? yes/no' no
    case "$answer" in yes) KEEP_BACKUP=true ;; no) KEEP_BACKUP=false ;; *) die 'Choose yes or no.' ;; esac
    printf '\nTarget: %s\nSource: %s\nSchedule: %s (+ up to 5 minutes)\nIf running: %s\nKeep backup: %s\n' \
        "$TARGET" "$(if [[ "$DOWNLOAD_LATEST" == true ]]; then printf '%s' "$RPM_URL"; else printf '%s' "$RPM_SOURCE_LOCAL"; fi)" "$CALENDAR" "$IF_RUNNING" "$KEEP_BACKUP"
    info 'Missed checks run after your user session starts; a check may run shortly after setup.'
    ask confirmation 'Enable this schedule? yes/no' no
    [[ "$confirmation" == yes ]] || { info 'Cancelled; no schedule was created.'; return 0; }
    write_schedule
}
wizard_main() {
    scheduler_paths
    local action=setup option
    local -a config_args=()
    while (( $# )); do
        option="$1"
        case "$option" in
            --help|-h) wizard_usage; return 0 ;;
            --status|--remove)
                [[ "$action" == setup ]] || die 'Select one action.'
                action="${option#--}"; shift ;;
            --config)
                [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die '--config requires a file'
                config_args+=(--config "$2"); shift 2 ;;
            --config=*) config_args+=(--config "${option#*=}"); shift ;;
            --no-config) config_args+=(--no-config); shift ;;
            *) die "Unknown argument: $option (see --help)" ;;
        esac
    done
    require_command systemctl
    require_command realpath
    case "$action" in
        status) schedule_status ;;
        remove) remove_schedule ;;
        setup) setup_schedule "${config_args[@]}" ;;
    esac
}
