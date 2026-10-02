#!/usr/bin/env bash
check_dependencies() {
    local command
    for command in rpm rpm2cpio cpio realpath mktemp flock find sort readlink; do require_command "$command"; done
    [[ -d /proc/self ]] || die 'This installer requires Linux /proc for safe process detection.'
    case "$RPM_SOURCE" in
        https://*) require_command curl ;;
        *://*) die 'Only local RPM files and HTTPS URLs are supported.' ;;
    esac
    [[ "$(rpm --eval '%{lua:print(rpm.vercmp("1", "2"))}')" == -1 ]] || die 'rpm with Lua rpm.vercmp support is required.'
}
acquire_rpm() {
    RPM_FILE="$WORKDIR/chatgpt.rpm"
    NOT_MODIFIED=false
    case "$RPM_SOURCE" in
        https://*)
            info "Downloading RPM: $RPM_SOURCE"
            local status
            local -a conditional=()
            if [[ "$FORCE" == false && -x "$TARGET/usr/bin/chatgpt" && -f "$TARGET/$METADATA_FILE" && \
                -s "$TARGET/.chatgpt-rpm-etag" && -f "$TARGET/.chatgpt-rpm-source" && \
                "$(cat "$TARGET/.chatgpt-rpm-source")" == "$RPM_SOURCE" ]]; then
                conditional=(--etag-compare "$TARGET/.chatgpt-rpm-etag")
            fi
            status="$(curl --fail --location --show-error --silent --retry 3 --retry-delay 2 \
                --connect-timeout 20 --max-time 1800 --proto '=https' --proto-redir '=https' \
                "${conditional[@]}" --etag-save "$WORKDIR/etag" --write-out '%{http_code}' \
                --output "$RPM_FILE" "$RPM_SOURCE")" || die 'RPM download failed; installation untouched.'
            if [[ "$status" == 304 && ${#conditional[@]} -gt 0 ]]; then NOT_MODIFIED=true; return 0; fi
            [[ "$status" == 200 ]] || die "Unexpected RPM download HTTP status: $status" ;;
        *)
            [[ -f "$RPM_SOURCE" && -r "$RPM_SOURCE" ]] || die "Cannot read RPM: $RPM_SOURCE"
            info "Using RPM: $RPM_SOURCE"
            cp -- "$RPM_SOURCE" "$RPM_FILE" ;;
    esac
    [[ -s "$RPM_FILE" ]] || die 'The RPM is empty.'
    rpm --checksig --nosignature "$RPM_FILE" || die 'RPM digest verification failed; installation untouched.'
}
extract_rpm() {
    STAGING_DIR="$WORKDIR/root"
    mkdir -p -- "$STAGING_DIR"
    info 'Extracting RPM without running package installation scripts...'
    rpm2cpio "$RPM_FILE" > "$WORKDIR/payload.cpio" || die 'Cannot decode RPM payload.'
    cpio --list --quiet < "$WORKDIR/payload.cpio" > "$WORKDIR/paths" || die 'Invalid RPM archive.'
    local path link resolved
    while IFS= read -r path; do
        case "/${path#./}/" in *'/../'*) die "Unsafe archive path: $path" ;; esac
        [[ "$path" != /* ]] || die "Absolute archive path: $path"
    done < "$WORKDIR/paths"
    rpm -qp --qf '[%{FILENAMES}\t%{FILELINKTOS}\n]' "$RPM_FILE" > "$WORKDIR/links" || die 'Cannot inspect RPM links.'
    while IFS=$'\t' read -r path link; do
        [[ -n "$link" ]] || continue
        [[ "$link" != /* ]] || die "Unsupported absolute RPM symlink: $path -> $link"
        resolved="$(realpath -m -- "$STAGING_DIR/$(dirname -- "${path#/}")/$link")"
        [[ "$resolved" == "$STAGING_DIR/"* ]] || die "RPM symlink escapes staging: $path"
    done < "$WORKDIR/links"
    (cd -- "$STAGING_DIR" && cpio --extract --make-directories --preserve-modification-time \
        --no-absolute-filenames --quiet < "$WORKDIR/payload.cpio") || die 'RPM extraction failed.'
    local executable="$STAGING_DIR/usr/bin/chatgpt"
    [[ -f "$executable" && -x "$executable" ]] || die 'RPM has no executable usr/bin/chatgpt (or its link is broken).'
    resolved="$(realpath -- "$executable")"
    [[ "$resolved" == "$STAGING_DIR/"* ]] || die 'ChatGPT executable points outside the package.'
    write_version_record
    if [[ "$RPM_SOURCE" == https://* && -s "$WORKDIR/etag" ]]; then
        cp -- "$WORKDIR/etag" "$STAGING_DIR/.chatgpt-rpm-etag"
        printf '%s\n' "$RPM_SOURCE" > "$STAGING_DIR/.chatgpt-rpm-source"
    fi
}
