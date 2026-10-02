#!/usr/bin/env bash
running_pids() {
    local entry executable pid
    for entry in /proc/[0-9]*/exe; do
        [[ -O "${entry%/exe}" ]] || continue
        executable="$(readlink -- "$entry" 2>/dev/null)" || continue
        if [[ "$executable" == "$TARGET/"* ]]; then
            pid="${entry#/proc/}"; printf '%s\n' "${pid%/exe}"
        fi
    done
}
close_application() {
    local -a pids=()
    mapfile -t pids < <(running_pids)
    (( ${#pids[@]} )) || return 0
    if [[ "$IF_RUNNING" == skip ]]; then
        info 'ChatGPT is running; deferring this update until a future run.'
        return 1
    fi
    warn 'ChatGPT must close before installation. Save your work; unsaved input may be lost.'
    confirm 'Close ChatGPT and continue?' || {
        warn 'Update cancelled. Use --yes to allow closing in an unattended run, or --if-running skip.'
        exit 3
    }
    notify_user "Save your work: ChatGPT will close in $CLOSE_DELAY seconds to install $NEW_EVR."
    (( CLOSE_DELAY == 0 )) || sleep "$CLOSE_DELAY"
    mapfile -t pids < <(running_pids)
    if (( ${#pids[@]} )); then
        info 'Closing ChatGPT with SIGTERM...'
        kill -TERM -- "${pids[@]}" 2>/dev/null || true
    fi
    local attempt
    for ((attempt=0; attempt<15; attempt++)); do
        mapfile -t pids < <(running_pids)
        (( ${#pids[@]} )) || return 0
        sleep 1
    done
    die 'ChatGPT did not exit within 15 seconds. Close it manually and retry.'
}
