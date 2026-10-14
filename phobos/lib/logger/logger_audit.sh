#!/bin/bash
# PHOBOS Logger - audit entry point.
#
# Reads Linux Audit records from stdin (as produced by
# `tail -F -n 0 /var/log/audit/audit.log`) and coalesces the multi-line records
# belonging to one `audit(<sec>.<ms>:<serial>)` id before handing the complete
# block to the audit collector.
#
# A single complete block may also be passed as the first argument, which is
# what `phobos logger ingest-audit <block>` uses.
#
# The service installed by `phobos logger enable` runs:
#   tail -F -n 0 /var/log/audit/audit.log | logger_audit.sh

# allow overriding, e.g. for development ($LIB_DIR/logger/...)
LIB_DIR="${LIB_DIR:-/usr/local/lib/phobos}"

source "$LIB_DIR/style.sh"
source "$LIB_DIR/logger/storage.sh"
source "$LIB_DIR/logger/logger.sh"
source "$LIB_DIR/logger/validation.sh"
source "$LIB_DIR/logger/collector.sh"

# prints the audit serial of a record line, e.g. "1634567890.123:456",
# or nothing when the line carries no audit id.
_logger_audit_id() {
    if [[ "$1" =~ audit\(([0-9]+\.[0-9]+:[0-9]+)\) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

# coalesces stdin records by audit serial and flushes each complete block
_logger_audit_stream() {
    local line
    local id=""
    local current_id=""
    local buffer=""

    # reading lines from stdin
    while IFS= read -r line; do
        # get id of current line
        id="$(_logger_audit_id "$line")"
        # check if id is different from previous (new event)
        if [[ -n "$id" && "$id" != "$current_id" ]]; then
            # if buffer is not empty, call method with this buffer
            [[ -n "$buffer" ]] && logger_collect_audit_block "$buffer"
            # resetting and updating variables
            buffer=""
            current_id="$id"
        fi
        # if buffer is not empty and there is no new id, simply adding new line to buffer with \n inbetween
        if [[ -n "$buffer" ]]; then
            buffer+=$'\n'
        fi
        buffer+="$line"
    done

    [[ -n "$buffer" ]] && logger_collect_audit_block "$buffer"
}

# if there was at least one block given, directly call method
if [[ $# -gt 0 ]]; then
    logger_collect_audit_block "$1"
    exit $?
fi

# if there is no block start stream mode, and wait for blocks to arrive via stdin
_logger_audit_stream

exit 0
