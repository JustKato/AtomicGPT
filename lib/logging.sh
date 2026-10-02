#!/usr/bin/env bash
# One private log for each selected installation/update attempt.
UPDATE_LOG='' UPDATE_OUTCOME=failed LOG_TEE_PID=''
begin_update_log() {
    local directory="$SCRIPT_DIR/logs" timestamp
    require_command tee
    require_command date
    [[ ! -L "$directory" && ( ! -e "$directory" || -d "$directory" ) ]] || die 'The project logs path must be a directory, not a symlink.'
    # SCRIPT_DIR already exists; only the logs directory needs this mode.
    # shellcheck disable=SC2174
    mkdir -p -m 700 -- "$directory"
    timestamp="$(date '+%Y%m%dT%H%M%S%z')"
    UPDATE_LOG="$(mktemp --suffix=.log "$directory/update-$timestamp.XXXXXX")"
    {
        printf 'AtomicGPT installation/update attempt\n'
        printf 'Started at: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%:z')"
        printf 'Target: %s\nFrom version: %s\nTo version: %s\nForce: %s\n\n' \
            "$TARGET" "${OLD_EVR:-not installed}" "$NEW_EVR" "$FORCE"
    } > "$UPDATE_LOG"
    exec {LOG_STDOUT_FD}>&1 {LOG_STDERR_FD}>&2
    # Let the parent record interruption before tee exits on pipe EOF.
    exec > >(trap '' INT TERM; exec tee -a -- "$UPDATE_LOG") 2>&1
    LOG_TEE_PID=$!
    info "Update log: $UPDATE_LOG"
}
finish_update_log() {
    local status="$1" outcome="$UPDATE_OUTCOME"
    [[ -n "$UPDATE_LOG" ]] || return 0
    if [[ "$COMMITTED" == true ]]; then
        if (( status == 0 )); then outcome=installed; else outcome='installed; integration or cleanup failed'; fi
    elif (( status == 3 )); then
        outcome=cancelled
    elif (( status == 130 || status == 143 )); then
        outcome=interrupted
    fi
    printf '\nFinished at: %s\nOutcome: %s\nExit code: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%:z')" "$outcome" "$status"
    # Close tee's input and wait so the final outcome is on disk before exit.
    if [[ -n "$LOG_TEE_PID" ]]; then
        exec 1>&"$LOG_STDOUT_FD" 2>&"$LOG_STDERR_FD"
        exec {LOG_STDOUT_FD}>&- {LOG_STDERR_FD}>&-
        wait "$LOG_TEE_PID" || warn "Could not finish writing update log: $UPDATE_LOG"
    fi
}
