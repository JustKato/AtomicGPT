#!/usr/bin/env bash
WORKDIR='' BACKUP_PATH='' SWAPPING=false COMMITTED=false HAD_TARGET=false
prepare_target() {
    validate_target_path
    if [[ -d "$TARGET" ]]; then HAD_TARGET=true; fi
    info "Installation target: $TARGET"
    local parent
    parent="$(dirname -- "$TARGET")"
    mkdir -p -- "$parent"
    exec {INSTALL_LOCK_FD}> "$parent/.$(basename -- "$TARGET").install.lock"
    flock -n "$INSTALL_LOCK_FD" || die 'Another installer is using this target.'
    WORKDIR="$(mktemp -d "$parent/.chatgpt-install.XXXXXX")"
}
cleanup_install() {
    local status=$?
    trap - EXIT INT TERM
    if [[ "$SWAPPING" == true && "$COMMITTED" == false ]]; then
        warn 'Installation failed; rolling back application files.'
        if [[ -n "$BACKUP_PATH" && -d "$BACKUP_PATH" ]]; then
            if [[ -e "$TARGET" ]]; then rm -rf -- "$TARGET"; fi
            mv -- "$BACKUP_PATH" "$TARGET" || warn "Restore the backup manually from $BACKUP_PATH"
        elif [[ "$HAD_TARGET" == false && -e "$TARGET" ]]; then
            rm -rf -- "$TARGET"
        fi
    fi
    if (( status != 0 )) && [[ "$COMMITTED" == true ]]; then
        warn 'Application files are installed, but a later integration/cleanup step failed.'
        [[ -z "$BACKUP_PATH" ]] || warn "Previous installation: $BACKUP_PATH"
    fi
    if [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then rm -rf -- "$WORKDIR"; fi
    finish_update_log "$status"
    exit "$status"
}
install_application() {
    if [[ -d "$TARGET" ]]; then
        BACKUP_PATH="$(mktemp -d "$TARGET.backup.XXXXXX")"
        rmdir -- "$BACKUP_PATH"
        SWAPPING=true
        mv -- "$TARGET" "$BACKUP_PATH"
    fi
    SWAPPING=true
    mv -- "$STAGING_DIR" "$TARGET"
    [[ -x "$TARGET/usr/bin/chatgpt" ]] || die 'Installed executable validation failed.'
    COMMITTED=true
    integrate_application
    if [[ -n "$BACKUP_PATH" ]]; then
        if [[ "$KEEP_BACKUP" == true ]]; then info "Previous installation retained: $BACKUP_PATH"; else rm -rf -- "$BACKUP_PATH"; fi
    fi
    success "Installed $NEW_EVR into $TARGET"
    info "Launch: $TARGET/usr/bin/chatgpt"
}
main() {
    local argument
    for argument in "$@"; do
        case "$argument" in --help|-h) usage; return 0 ;; --version) printf 'AtomicGPT %s\n' "$ATOMICGPT_VERSION"; return 0 ;; esac
    done
    require_command realpath
    load_config "$@"
    parse_args "$@"
    validate_config
    check_dependencies
    trap cleanup_install EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    prepare_target
    acquire_rpm
    if [[ "$NOT_MODIFIED" == true ]]; then info 'The remote RPM is unchanged; already up to date.'; return 0; fi
    query_candidate_version
    # Don't invoke mutation functions inside if/!: that disables Bash errexit.
    if ! should_install; then return 0; fi
    if [[ "$CHECK_ONLY" == true ]]; then info 'Check complete; no application changes made.'; return 0; fi
    begin_update_log
    extract_rpm
    if ! close_application; then UPDATE_OUTCOME=deferred; return 0; fi
    install_application
}
