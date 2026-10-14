#!/bin/bash
# central style library for all PHOBOS CLI output
#
# Provides ANSI color codes and helper functions so every user-facing
# message is consistent and professional-looking.
#
# Colors are automatically disabled when stdout is not a terminal
# (e.g. when output is piped or redirected to a file) so that log
# files and pipelines stay clean.  The behaviour can be forced with
# PHOBOS_COLOR=1 (always on) or PHOBOS_COLOR=0 (always off).

# ---------------------------------------------------------------------------
# TTY detection
# ---------------------------------------------------------------------------
if [[ "${PHOBOS_COLOR:-}" == "1" ]]; then
    PHOBOS_COLOR_ENABLED=1
elif [[ "${PHOBOS_COLOR:-}" == "0" ]]; then
    PHOBOS_COLOR_ENABLED=0
elif [[ -t 1 ]]; then
    PHOBOS_COLOR_ENABLED=1
else
    PHOBOS_COLOR_ENABLED=0
fi

# ---------------------------------------------------------------------------
# ANSI code definitions
# ---------------------------------------------------------------------------
if [[ "$PHOBOS_COLOR_ENABLED" -eq 1 ]]; then
    # formatting
    readonly C_RESET=$'\033[0m'
    readonly C_BOLD=$'\033[1m'
    readonly C_DIM=$'\033[2m'
    readonly C_UNDERLINE=$'\033[4m'

    # foreground colors
    readonly C_RED=$'\033[31m'
    readonly C_GREEN=$'\033[32m'
    readonly C_YELLOW=$'\033[33m'
    readonly C_BLUE=$'\033[34m'
    readonly C_MAGENTA=$'\033[35m'
    readonly C_CYAN=$'\033[36m'
    readonly C_WHITE=$'\033[37m'
    readonly C_GRAY=$'\033[90m'

    # bright foreground colors
    readonly C_BRED=$'\033[91m'
    readonly C_BGREEN=$'\033[92m'
    readonly C_BYELLOW=$'\033[93m'
    readonly C_BBLUE=$'\033[94m'
    readonly C_BMAGENTA=$'\033[95m'
    readonly C_BCYAN=$'\033[96m'
else
    readonly C_RESET=''
    readonly C_BOLD=''
    readonly C_DIM=''
    readonly C_UNDERLINE=''

    readonly C_RED=''
    readonly C_GREEN=''
    readonly C_YELLOW=''
    readonly C_BLUE=''
    readonly C_MAGENTA=''
    readonly C_CYAN=''
    readonly C_WHITE=''
    readonly C_GRAY=''

    readonly C_BRED=''
    readonly C_BGREEN=''
    readonly C_BYELLOW=''
    readonly C_BBLUE=''
    readonly C_BMAGENTA=''
    readonly C_BCYAN=''
fi

# ---------------------------------------------------------------------------
# status glyphs (single-source for every icon used in the CLI)
# ---------------------------------------------------------------------------
readonly GLYPH_INFO='·'
readonly GLYPH_SUCCESS='✓'
readonly GLYPH_WARN='!'
readonly GLYPH_ERROR='✗'
readonly GLYPH_ARROW='→'

# ---------------------------------------------------------------------------
# output helpers
# ---------------------------------------------------------------------------

# styled one-line label + message, e.g. "[ ok ] something happened"
# usage: _phobos_label <color> <glyph> <label-text> [message...]
_phobos_label() {
    local color="$1" glyph="$2" label="$3"
    shift 3
    printf '%s[%s %s]%s %s%s%s\n' \
        "$C_DIM" "$color" "$glyph $label" "$C_RESET" \
        "$C_BOLD" "$*" "$C_RESET"
}

# info  – neutral informational message (cyan)
info() {
    _phobos_label "$C_CYAN" "$GLYPH_INFO" "info" "$@"
}

# success – positive outcome (green)
success() {
    _phobos_label "$C_GREEN" "$GLYPH_SUCCESS" "ok" "$@"
}

# warn – non-fatal warning (yellow)
warn() {
    _phobos_label "$C_YELLOW" "$GLYPH_WARN" "warn" "$@"
}

# error – fatal error, written to stderr (red)
error() {
    _phobos_label "$C_RED" "$GLYPH_ERROR" "error" "$@" >&2
}

# hint – secondary / follow-up information (dim gray)
hint() {
    printf '%s       %s %s%s\n' "$C_DIM" "$GLYPH_ARROW" "$*" "$C_RESET"
}

# section header with a drawn underline, e.g. "── PHOBOS Scheduler ──"
# usage: header <title> [separator-char]
header() {
    local title="$1" sep="${2:--}"
    local width=${#title}
    local line=''
    for ((i = 0; i < width + 2; i++)); do
        line+="$sep"
    done
    printf '%s%s%s\n%s%s%s\n' \
        "$C_BOLD$C_WHITE" "$title" "$C_RESET" \
        "$C_DIM" "$line" "$C_RESET"
}

# bold label + value pair used in status tables
# usage: field <label> <value> [value-color]
field() {
    local label="$1" value="$2" color="${3:-$C_WHITE}"
    printf '  %s%-18s%s %s%s%s\n' \
        "$C_GRAY" "${label}" "$C_RESET" \
        "$C_BOLD$color" "$value" "$C_RESET"
}

# key=value style line (dim key, bright value)
kv() {
    local key="$1" value="$2"
    printf '  %s%-14s%s %s%s%s\n' \
        "$C_DIM" "${key}" "$C_RESET" \
        "$C_WHITE" "$value" "$C_RESET"
}

# severity colorizer – maps a PHOBOS severity string to a colored label
# usage: severity_label <SEVERITY>
severity_label() {
    local sev="$1" color
    case "$sev" in
        INFO)     color="$C_CYAN" ;;
        LOW)      color="$C_GREEN" ;;
        MEDIUM)   color="$C_YELLOW" ;;
        HIGH)     color="$C_BRED" ;;
        CRITICAL) color="$C_RED" ;;
        *)        color="$C_WHITE" ;;
    esac
    printf '%s%s%s' "$C_BOLD$color" "$sev" "$C_RESET"
}

# status colorizer – maps SUCCESS / FAILURE / etc. to a colored label
# usage: status_label <STATUS>
status_label() {
    local st="$1" color
    case "$st" in
        SUCCESS)  color="$C_GREEN" ;;
        FAILURE)  color="$C_RED" ;;
        DENIED)   color="$C_BRED" ;;
        *)        color="$C_WHITE" ;;
    esac
    printf '%s%s%s' "$C_BOLD$color" "$st" "$C_RESET"
}
