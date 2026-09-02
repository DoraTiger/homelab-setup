#!/bin/bash

homelab_parse_init_args() {
    CLI_SILENT=0
    CLI_UPGRADE=0
    CLI_PROXY=""
    CLI_WORKSPACE_ROOT=""
    CLI_SELECTORS=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --silent|-s) CLI_SILENT=1; shift ;;
            --upgrade|-u) CLI_UPGRADE=1; shift ;;
            --proxy)
                [ "$#" -ge 2 ] && [ -n "$2" ] || { echo "--proxy requires a value" >&2; return 1; }
                CLI_PROXY="$2"; shift 2 ;;
            --workspace-root)
                [ "$#" -ge 2 ] && [ -n "$2" ] || { echo "--workspace-root requires a value" >&2; return 1; }
                CLI_WORKSPACE_ROOT="$2"; shift 2 ;;
            --) shift; CLI_SELECTORS+=("$@"); break ;;
            -*) echo "unknown option: $1" >&2; return 1 ;;
            *) CLI_SELECTORS+=("$1"); shift ;;
        esac
    done
}

homelab_resolve_module() {
    local selector="$1"
    shift
    local module base prefix name selector_number prefix_number
    local matches=()

    for module in "$@"; do
        base="$(basename "$module")"
        prefix="${base%%-*}"
        name="${base#*-}"
        name="${name%.sh}"
        if [ "$selector" = "$base" ] || [ "$selector" = "$name" ]; then
            matches+=("$module")
        elif [[ "$selector" =~ ^[0-9]+$ ]] && [[ "$prefix" =~ ^[0-9]+$ ]]; then
            selector_number=$((10#$selector))
            prefix_number=$((10#$prefix))
            [ "$selector_number" -ne "$prefix_number" ] || matches+=("$module")
        fi
    done

    [ "${#matches[@]}" -eq 1 ] || {
        if [ "${#matches[@]}" -eq 0 ]; then
            echo "unknown module selector: $selector" >&2
        else
            echo "ambiguous module selector: $selector" >&2
        fi
        return 1
    }
    printf '%s\n' "${matches[0]}"
}

homelab_unique_modules() {
    local modules=() selectors=() item resolved in_selectors=0
    local -A seen=()
    for item in "$@"; do
        if [ "$item" = -- ] && [ "$in_selectors" -eq 0 ]; then
            in_selectors=1
        elif [ "$in_selectors" -eq 0 ]; then
            modules+=("$item")
        else
            selectors+=("$item")
        fi
    done
    [ "$in_selectors" -eq 1 ] || { echo "module/selector separator is missing" >&2; return 1; }

    for item in "${selectors[@]}"; do
        resolved="$(homelab_resolve_module "$item" "${modules[@]}")" || return 1
        if [ -z "${seen[$resolved]:-}" ]; then
            printf '%s\n' "$resolved"
            seen[$resolved]=1
        fi
    done
}
