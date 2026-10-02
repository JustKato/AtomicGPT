#!/usr/bin/env bash
DEFAULT_RPM_URL='https://persistent.oaistatic.com/codex-app-prod/linux/rpm/latest/chatgpt.x86_64.rpm'
CONFIG_KEYS=(INSTALL_DIR DOWNLOAD_LATEST RPM_PATH RPM_URL INTEGRATE_DESKTOP KEEP_BACKUP IF_RUNNING CLOSE_DELAY)

read_env_file() {
    local file="$1" line key value line_number=0
    [[ -f "$file" ]] || die "Configuration file not found: $file"
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))
        line="$(trim "${line%$'\r'}")"
        [[ -z "$line" || "$line" == \#* ]] && continue
        [[ "$line" == *=* ]] || die "$file:$line_number: expected KEY=value"
        key="$(trim "${line%%=*}")"
        value="$(trim "${line#*=}")"
        case "$key" in
            INSTALL_DIR|DOWNLOAD_LATEST|RPM_PATH|RPM_URL|INTEGRATE_DESKTOP|KEEP_BACKUP|IF_RUNNING|CLOSE_DELAY) ;;
            *) die "$file:$line_number: unknown setting: $key" ;;
        esac
        if [[ "$value" == \"* || "$value" == \'* ]]; then
            [[ ${#value} -ge 2 && "${value: -1}" == "${value:0:1}" ]] || die "$file:$line_number: unmatched quote"
            value="${value:1:${#value}-2}"
        fi
        printf -v "$key" '%s' "$value"
    done < "$file"
}

load_config() {
    local key config_file="$SCRIPT_DIR/.env" explicit=false use_config=true
    local -A overrides=()
    for key in "${CONFIG_KEYS[@]}"; do
        if [[ -v "$key" ]]; then overrides["$key"]="${!key}"; fi
    done
    INSTALL_DIR="$HOME/Programs/ChatGPT"
    DOWNLOAD_LATEST=true RPM_PATH='' RPM_URL="$DEFAULT_RPM_URL"
    INTEGRATE_DESKTOP=true KEEP_BACKUP=false IF_RUNNING=close CLOSE_DELAY=5
    local -a args=("$@")
    local index
    for ((index=0; index<${#args[@]}; index++)); do
        case "${args[index]}" in
            --config)
                (( index + 1 < ${#args[@]} )) || die '--config requires a file'
                config_file="${args[index+1]}"; explicit=true; index=$((index + 1)) ;;
            --config=*) config_file="${args[index]#*=}"; explicit=true ;;
            --no-config) use_config=false ;;
        esac
    done
    [[ "$explicit" != true || "$use_config" != false ]] || die 'Use either --config or --no-config.'
    CONFIG_FILE=''
    if [[ "$use_config" == true && ( -f "$config_file" || "$explicit" == true ) ]]; then
        CONFIG_FILE="$(realpath -m -- "$(expand_home "$config_file")")"
        read_env_file "$CONFIG_FILE"
    fi
    for key in "${!overrides[@]}"; do printf -v "$key" '%s' "${overrides[$key]}"; done
}

validate_config() {
    local key
    for key in "${CONFIG_KEYS[@]}"; do valid_line "${!key}"; done
    for key in DOWNLOAD_LATEST INTEGRATE_DESKTOP KEEP_BACKUP; do
        case "${!key}" in true|false) ;; *) die "$key must be true or false" ;; esac
    done
    case "$IF_RUNNING" in close|skip) ;; *) die 'IF_RUNNING must be close or skip' ;; esac
    [[ "$CLOSE_DELAY" =~ ^[0-9]+$ && ${#CLOSE_DELAY} -le 2 ]] || die 'CLOSE_DELAY must be 0 through 60 seconds'
    CLOSE_DELAY=$((10#$CLOSE_DELAY))
    (( CLOSE_DELAY <= 60 )) || die 'CLOSE_DELAY must be 0 through 60 seconds'
    [[ -n "$INSTALL_DIR" ]] || die 'INSTALL_DIR cannot be empty'
    TARGET="$(expand_home "$INSTALL_DIR")"
    if [[ "$DOWNLOAD_LATEST" == true ]]; then
        RPM_SOURCE="$RPM_URL"
        [[ "$RPM_SOURCE" == https://* ]] || die 'RPM_URL must be an HTTPS URL'
    else
        [[ -n "$RPM_PATH" ]] || die 'Set RPM_PATH or use --rpm when DOWNLOAD_LATEST=false'
        RPM_SOURCE="$(expand_home "$RPM_PATH")"
        if [[ "$RPM_SOURCE" != /* && "$RPM_SOURCE" != *://* && -n "$CONFIG_FILE" ]]; then
            RPM_SOURCE="$(dirname -- "$CONFIG_FILE")/$RPM_SOURCE"
        fi
    fi
    BIN_DIR="$HOME/.local/bin"
    BIN_LINK="$BIN_DIR/chatgpt"
    DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    DESKTOP_ID=chatgpt.desktop
}
