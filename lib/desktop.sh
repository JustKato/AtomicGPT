#!/usr/bin/env bash
desktop_escape() {
    local value="$1"
    value="${value//\\/\\\\}"; value="${value//\"/\\\"}"
    value="${value//\$/\\\$}"; value="${value//\`/\\\`}"
    value="${value//%/%%}"
    # Desktop string unescaping happens before Exec argument unquoting.
    value="${value//\\/\\\\}"
    printf '%s' "$value"
}
integrate_application() {
    [[ "$INTEGRATE_DESKTOP" == true ]] || return 0
    mkdir -p -- "$BIN_DIR" "$DESKTOP_DIR"
    local launcher="$TARGET/usr/bin/chatgpt"
    if [[ -e "$BIN_LINK" && ! -L "$BIN_LINK" ]]; then
        warn "Leaving existing non-symlink command untouched: $BIN_LINK"
    else
        ln -sfn -- "$TARGET/usr/bin/chatgpt" "$BIN_LINK"
        launcher="$BIN_LINK"
    fi
    local icon=chatgpt path desktop_file="$DESKTOP_DIR/$DESKTOP_ID"
    while IFS= read -r path; do icon="$path"; break; done < <(
        find "$TARGET/usr/share" -type f \( -iname '*chatgpt*.png' -o -iname '*chatgpt*.svg' \) 2>/dev/null | sort || true
    )
    local temp
    temp="$(mktemp "$DESKTOP_DIR/.chatgpt-desktop.XXXXXX")"
    cat > "$temp" <<EOF
[Desktop Entry]
Name=ChatGPT
Comment=ChatGPT by OpenAI
Exec="$(desktop_escape "$launcher")" %U
Icon=${icon//\\/\\\\}
Terminal=false
Type=Application
Categories=Network;
StartupNotify=true
StartupWMClass=ChatGPT
MimeType=x-scheme-handler/codex;
EOF
    chmod 644 "$temp"
    mv -f -- "$temp" "$desktop_file"
    if command_exists xdg-mime; then
        xdg-mime default "$DESKTOP_ID" x-scheme-handler/codex || warn 'Could not register the codex:// handler.'
    fi
    if command_exists update-desktop-database; then update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true; fi
    if command_exists kbuildsycoca6; then kbuildsycoca6 >/dev/null 2>&1 || true; fi
    success "Desktop launcher: $desktop_file"
    case ":$PATH:" in *":$BIN_DIR:"*) ;; *) warn "Add $BIN_DIR to PATH to run chatgpt from your shell." ;; esac
}
