#!/usr/bin/env bash
METADATA_FILE=.chatgpt-install-info
valid_rpm_version() {
    [[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[a-zA-Z0-9._+~^]+$ && "$3" =~ ^[a-zA-Z0-9._+~^]+$ ]]
}
query_candidate_version() {
    local metadata
    metadata="$(rpm -qp --qf '%{NAME}\t%{EPOCHNUM}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\n' "$RPM_FILE")" || die 'Cannot read RPM metadata.'
    IFS=$'\t' read -r PACKAGE_NAME NEW_EPOCH NEW_VERSION NEW_RELEASE PACKAGE_ARCH <<< "$metadata"
    [[ "$PACKAGE_NAME" == chatgpt ]] || die "Expected a chatgpt RPM; found: $PACKAGE_NAME"
    valid_rpm_version "$NEW_EPOCH" "$NEW_VERSION" "$NEW_RELEASE" || die 'Invalid RPM version metadata.'
    [[ "$PACKAGE_ARCH" == "$(uname -m)" ]] || die "RPM architecture $PACKAGE_ARCH does not match $(uname -m)"
    NEW_EVR="$NEW_EPOCH:$NEW_VERSION-$NEW_RELEASE"
}
read_installed_version() {
    OLD_EPOCH='' OLD_VERSION='' OLD_RELEASE='' OLD_EVR=unknown
    local key value extra
    [[ -f "$TARGET/$METADATA_FILE" ]] || return 0
    while IFS='=' read -r key value extra; do
        [[ -z "$extra" ]] || die 'Invalid installed-version record.'
        case "$key" in
            EPOCH) OLD_EPOCH="$value" ;;
            VERSION) OLD_VERSION="$value" ;;
            RELEASE) OLD_RELEASE="$value" ;;
        esac
    done < "$TARGET/$METADATA_FILE"
    valid_rpm_version "$OLD_EPOCH" "$OLD_VERSION" "$OLD_RELEASE" || die "Invalid $METADATA_FILE; restore it or remove it and use --force."
    OLD_EVR="$OLD_EPOCH:$OLD_VERSION-$OLD_RELEASE"
}
compare_versions() {
    # RPM ordering, including epochs, packaging releases, ~ and ^. No eval.
    RPM_NEW_EPOCH="$NEW_EPOCH" RPM_NEW_VERSION="$NEW_VERSION" RPM_NEW_RELEASE="$NEW_RELEASE" \
    RPM_OLD_EPOCH="$OLD_EPOCH" RPM_OLD_VERSION="$OLD_VERSION" RPM_OLD_RELEASE="$OLD_RELEASE" \
    rpm --eval '%{lua:local result = 0; for _, part in ipairs({"EPOCH", "VERSION", "RELEASE"}) do result = rpm.vercmp(os.getenv("RPM_NEW_" .. part), os.getenv("RPM_OLD_" .. part)); if result ~= 0 then break end end; print(result)}'
}
should_install() {
    info "Candidate version: $NEW_EVR"
    if [[ ! -e "$TARGET" ]]; then
        info 'No existing installation; ready to install.'
        return 0
    fi
    read_installed_version
    info "Installed version: $OLD_EVR"
    if [[ "$OLD_EVR" == unknown ]]; then
        warn 'This folder has no RPM version record (for example, a manual extraction).'
        if [[ "$FORCE" != true ]]; then
            [[ "$CHECK_ONLY" == true ]] && return 1
            die 'Use --force once to replace/adopt this installation and begin tracking versions.'
        fi
        warn '--force: replacing the untracked installation.'
        return 0
    fi
    local comparison
    comparison="$(compare_versions)" || die 'RPM version comparison failed.'
    case "$comparison" in -1|0|1) ;; *) die "Unexpected RPM version comparison: $comparison" ;; esac
    if [[ "$FORCE" == true ]]; then
        warn '--force: installing even if the package is equal or older.'
        return 0
    fi
    if [[ "$comparison" == 1 ]]; then info 'A newer version is available.'; return 0; fi
    info 'Already up to date; the candidate is equal to or older than the installation.'
    return 1
}
write_version_record() {
    printf 'EPOCH=%s\nVERSION=%s\nRELEASE=%s\n' "$NEW_EPOCH" "$NEW_VERSION" "$NEW_RELEASE" > "$STAGING_DIR/$METADATA_FILE"
}
