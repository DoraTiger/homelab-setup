#!/bin/bash

# Interactive prompts. SILENT is provided by common.sh.

prompt_choice() {
    local msg="$1" default="$2"
    shift 2
    local options=("$@") choice i
    if [ "$SILENT" = "1" ]; then echo "$default"; return; fi
    echo "" >&2
    echo -e "\033[0;33m  $msg\033[0m" >&2
    for i in "${!options[@]}"; do
        printf '    [%d] %s%s\n' "$((i + 1))" "${options[$i]}" "$([ "${options[$i]}" = "$default" ] && echo ' (默认)')" >&2
    done
    read -rp "  请选择 [1-${#options[@]}]: " choice
    choice="${choice:-$default}"
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
        echo "${options[$((choice - 1))]}"
    else
        echo "$default"
    fi
}

prompt_yesno() {
    local msg="$1" default="${2:-y}" ans
    if [ "$SILENT" = "1" ]; then [ "$default" = "y" ]; return; fi
    if [ "$default" = "y" ]; then
        read -rp "  $msg [Y/n]: " ans
    else
        read -rp "  $msg [y/N]: " ans
    fi
    ans="${ans:-$default}"
    [[ "$ans" =~ ^[Yy]$ ]]
}

prompt_input() {
    local msg="$1" default="$2" input
    if [ "$SILENT" = "1" ]; then echo "$default"; return; fi
    read -rp "  $msg [$default]: " input
    echo "${input:-$default}"
}

prompt_secret() {
    local msg="$1" val val2
    if [ "$SILENT" = "1" ]; then echo ""; return; fi
    read -rs -p "  $msg: " val; echo "" >&2
    read -rs -p "  请再次输入: " val2; echo "" >&2
    [ "$val" = "$val2" ] || { log_error "两次输入不一致"; return 1; }
    echo "$val"
}

prompt_table() {
    local header="$1"
    shift
    local rows=("$@") row line cell sep="  +" i w
    local -a hdr_cols cells widths=()
    IFS='|' read -ra hdr_cols <<< "$header"
    local ncols="${#hdr_cols[@]}"
    for cell in "${hdr_cols[@]}"; do widths+=("${#cell}"); done
    for row in "${rows[@]}"; do
        IFS='|' read -ra cells <<< "$row"
        for ((i = 0; i < ncols; i++)); do
            [ "${#cells[$i]}" -le "${widths[$i]}" ] || widths[$i]="${#cells[$i]}"
        done
    done
    for w in "${widths[@]}"; do
        for ((i = 0; i < w + 2; i++)); do sep+="-"; done
        sep+="+"
    done
    echo "$sep"
    line="  |"
    for ((i = 0; i < ncols; i++)); do
        printf -v cell "%-$((${widths[$i]} + 1))s " "${hdr_cols[$i]}"
        line+="$cell|"
    done
    echo "$line"
    echo "$sep"
    for row in "${rows[@]}"; do
        IFS='|' read -ra cells <<< "$row"
        line="  |"
        for ((i = 0; i < ncols; i++)); do
            printf -v cell "%-$((${widths[$i]} + 1))s " "${cells[$i]}"
            line+="$cell|"
        done
        echo "$line"
    done
    echo "$sep"
}
