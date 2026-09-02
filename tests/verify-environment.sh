#!/bin/bash

set -uo pipefail

failures=0
passes=0
skips=0

run_clean_login() {
    env \
        -u BASH_ENV \
        -u FNM_DIR \
        -u FNM_INSTALL_DIR \
        -u FNM_MULTISHELL_PATH \
        -u GOROOT \
        -u GOPATH \
        -u GOBIN \
        -u GOCACHE \
        -u GOMODCACHE \
        -u SDKMAN_DIR \
        -u CARGO_HOME \
        -u RUSTUP_HOME \
        -u TEXLIVE_DIR \
        PATH=/usr/local/bin:/usr/bin:/bin \
        bash -lc "$1"
}

check_login_command() {
    local label="$1"
    local command_name="$2"
    local evidence="$3"
    local resolved

    if [ ! -e "$evidence" ] && [ ! -L "$evidence" ]; then
        printf 'SKIP  %-18s installation evidence not found: %s\n' "$label" "$evidence"
        skips=$((skips + 1))
        return
    fi

    resolved="$(run_clean_login "command -v $command_name" 2>/dev/null)"
    if [ -n "$resolved" ]; then
        printf 'PASS  %-18s %s\n' "$label" "$resolved"
        passes=$((passes + 1))
    else
        printf 'FAIL  %-18s missing from non-interactive login PATH\n' "$label"
        failures=$((failures + 1))
    fi
}

check_login_variable() {
    local label="$1"
    local variable_name="$2"
    local expected="$3"
    local actual

    actual="$(run_clean_login "printf '%s' \"\${$variable_name:-}\"" 2>/dev/null)"
    if [ "$actual" = "$expected" ]; then
        printf 'PASS  %-18s %s\n' "$label" "$actual"
        passes=$((passes + 1))
    else
        printf 'FAIL  %-18s expected=%s actual=%s\n' "$label" "$expected" "${actual:-<empty>}"
        failures=$((failures + 1))
    fi
}

check_login_command "SSH" ssh /usr/bin/ssh
check_login_command "Git" git /usr/bin/git
check_login_command "Docker" docker /usr/bin/docker
check_login_command "Conda" conda "$HOME/.local/opt/miniconda3/bin/conda"
check_login_command "Python" python "$HOME/.local/opt/miniconda3/bin/python"
check_login_command "Python 3" python3 /usr/bin/python3
check_login_command "pip" pip "$HOME/.local/opt/miniconda3/bin/pip"
check_login_command "Go" go "$HOME/.local/opt/go/current/bin/go"
check_login_command "gofmt" gofmt "$HOME/.local/opt/go/current/bin/gofmt"
check_login_command "Java" java "$HOME/.local/opt/sdkman/candidates/java/current/bin/java"
check_login_command "javac" javac "$HOME/.local/opt/sdkman/candidates/java/current/bin/javac"
check_login_command "Maven" mvn "$HOME/.local/opt/sdkman/candidates/maven/current/bin/mvn"
check_login_command "fnm" fnm "$HOME/.local/opt/fnm/fnm"
check_login_command "Node.js" node "$HOME/.local/share/fnm/aliases/default/bin/node"
check_login_command "npm" npm "$HOME/.local/npm-global/bin/npm"
check_login_command "npx" npx "$HOME/.local/npm-global/bin/npx"
check_login_command "Perl" perl /usr/bin/perl
check_login_command "CPAN" cpan /usr/bin/cpan
check_login_command "R" R /usr/bin/R
check_login_command "Rscript" Rscript /usr/bin/Rscript
check_login_command "rustc" rustc "$HOME/.local/opt/cargo/bin/rustc"
check_login_command "cargo" cargo "$HOME/.local/opt/cargo/bin/cargo"
check_login_command "rustup" rustup "$HOME/.local/opt/cargo/bin/rustup"
check_login_command "TeX" tex "$HOME/.local/opt/texlive/2026/bin/x86_64-linux/tex"
check_login_command "LaTeX" latex "$HOME/.local/opt/texlive/2026/bin/x86_64-linux/latex"
check_login_command "XeLaTeX" xelatex "$HOME/.local/opt/texlive/2026/bin/x86_64-linux/xelatex"
check_login_command "tlmgr" tlmgr "$HOME/.local/opt/texlive/2026/bin/x86_64-linux/tlmgr"
check_login_command "Zellij" zellij "$HOME/.local/bin/zellij"

check_login_variable "GOROOT" GOROOT "$HOME/.local/opt/go/current"
check_login_variable "GOPATH" GOPATH "$HOME/workspace/cache/go"
check_login_variable "FNM_DIR" FNM_DIR "$HOME/.local/share/fnm"
check_login_variable "SDKMAN_DIR" SDKMAN_DIR "$HOME/.local/opt/sdkman"
check_login_variable "CARGO_HOME" CARGO_HOME "$HOME/.local/opt/cargo"
check_login_variable "RUSTUP_HOME" RUSTUP_HOME "$HOME/.local/opt/rustup"
check_login_variable "TEXLIVE_DIR" TEXLIVE_DIR "$HOME/.local/opt/texlive/2026"

if dpkg -s obsidian >/dev/null 2>&1; then
    check_login_command "Obsidian CLI" obsidian /usr/bin/obsidian
else
    printf 'SKIP  %-18s package is not installed\n' "Obsidian"
    skips=$((skips + 1))
fi

if [ -x "$HOME/.local/opt/zotero/zotero" ]; then
    printf 'PASS  %-18s %s\n' "Zotero executable" "$HOME/.local/opt/zotero/zotero"
    passes=$((passes + 1))
else
    printf 'SKIP  %-18s executable is not installed\n' "Zotero"
    skips=$((skips + 1))
fi

if command -v docker >/dev/null 2>&1 && run_clean_login 'docker compose version >/dev/null 2>&1'; then
    printf 'PASS  %-18s available\n' "Docker Compose"
    passes=$((passes + 1))
elif [ -x /usr/bin/docker ]; then
    printf 'FAIL  %-18s unavailable in non-interactive login shell\n' "Docker Compose"
    failures=$((failures + 1))
else
    printf 'SKIP  %-18s Docker is not installed\n' "Docker Compose"
    skips=$((skips + 1))
fi

printf '\nSummary: %d passed, %d skipped, %d failed\n' "$passes" "$skips" "$failures"
[ "$failures" -eq 0 ]
