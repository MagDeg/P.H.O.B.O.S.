#!/bin/bash

# callback for logger_show(): pretty-prints one event block.
_logger_show_event() {
    local line
    local key
    local label

    # increases shown events
    ((LOGGER_SHOW_COUNT++))

    echo "Event #$LOGGER_SHOW_COUNT"
    echo "----------------------------------------"

    # reading each line in the event body
    while IFS= read -r line; do
        # everything before first =
        key="${line%%=*}"

        case "$key" in
            id)        label="ID" ;;
            timestamp) label="Timestamp" ;;
            category)  label="Category" ;;
            action)    label="Action" ;;
            user)      label="User" ;;
            source)    label="Source" ;;
            target)    label="Target" ;;
            device)    label="Device" ;;
            status)    label="Status" ;;
            severity)  label="Severity" ;;
            details)   label="Details" ;;
            *)         continue ;;
        esac

        # prints left aligned label and value
        printf '%-11s%s\n' "$label:" "${line#*=}"
    done <<< "$LOGGER_EVENT_BODY"

    echo ""
}

# prints every logged event
# requires root.
logger_show() {
    logger_require_root "logger show" || return 1

    # if no log-file exists
    if [[ ! -f "$EVENT_LOG" ]]; then
        logger_error "Event log not found."
        return 1
    fi

    echo "PHOBOS Logger Events"
    echo "===================="
    echo ""

    LOGGER_SHOW_COUNT=0
    # iterating through every event in log file
    logger_chain_walk "$EVENT_LOG" _logger_show_event

    echo "Total events: $LOGGER_SHOW_COUNT"
}

# recomputes the hash chain and reports whether it is intact
# requires root.
logger_verify_chain() {
    logger_require_root "logger verify" || return 1

    if logger_chain_check; then
        echo "PHOBOS Logger Integrity"
        echo "-----------------------"
        echo "Events checked: $LOGGER_CHAIN_EVENTS"
        echo "Chain status:   VALID"
        echo "Final hash:     $LOGGER_CHAIN_HASH"
        return 0
    fi

    logger_error "Integrity chain: INVALID"
    if [[ -n "$LOGGER_CHAIN_FAIL_REASON" ]]; then
        logger_error "Reason: $LOGGER_CHAIN_FAIL_REASON"
    fi
    if (( LOGGER_CHAIN_FAIL_EVENT > 0 )); then
        logger_error "Failed at event: $LOGGER_CHAIN_FAIL_EVENT"
    fi
    return 1
}