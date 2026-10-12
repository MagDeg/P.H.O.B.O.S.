#!/bin/bash

# route a journal line to the relevant collector.
# collectors return 0 when they recognize a line and 1 otherwise, so the
# first match wins. Unrecognized lines are ignored (not an error).
logger_collect_journal_line() {
    local line="$1"

    # if line is empty
    [[ -n "$line" ]] || return 1

    # if collector returns 1, go to the next command
    # if collector returns 0 (recognized) stop
    logger_collect_sudo "$line" && return 0
    logger_collect_auth "$line" && return 0

    return 0
}
