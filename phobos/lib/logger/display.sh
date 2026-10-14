#!/bin/bash

# callback for logger_show(): pretty-prints one event block.
_logger_show_event() {
    local line
    local key
    local value
    local label

    # increases shown events
    ((LOGGER_SHOW_COUNT++))

    printf '%sEvent #%s%s\n' "$C_BOLD$C_CYAN" "$LOGGER_SHOW_COUNT" "$C_RESET"
    printf '%s----------------------------------------%s\n' "$C_DIM" "$C_RESET"

    # reading each line in the event body
    while IFS= read -r line; do
        # everything before first =
        key="${line%%=*}"
        value="${line#*=}"

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

        # color the two semantically important fields
        case "$key" in
            severity)
                printf '%s%-11s%s %s\n' "$C_GRAY" "$label:" "$C_RESET" "$(severity_label "$value")"
                ;;
            status)
                printf '%s%-11s%s %s\n' "$C_GRAY" "$label:" "$C_RESET" "$(status_label "$value")"
                ;;
            *)
                # prints left aligned label and value
                printf '%s%-11s%s %s%s%s\n' "$C_GRAY" "$label:" "$C_RESET" "$C_WHITE" "$value" "$C_RESET"
                ;;
        esac
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

    header "PHOBOS Logger Events"
    echo ""

    LOGGER_SHOW_COUNT=0
    # iterating through every event in log file
    logger_chain_walk "$EVENT_LOG" _logger_show_event

    printf '%sTotal events:%s %s%s%s\n' "$C_GRAY" "$C_RESET" "$C_BOLD$C_CYAN" "$LOGGER_SHOW_COUNT" "$C_RESET"
}

# recomputes the hash chain and reports whether it is intact
# requires root.
logger_verify_chain() {
    logger_require_root "logger verify" || return 1

    if logger_chain_check; then
        header "PHOBOS Logger Integrity"
        field "Events checked:" "$LOGGER_CHAIN_EVENTS"
        field "Chain status:"   "VALID" "$C_GREEN"
        field "Final hash:"     "$LOGGER_CHAIN_HASH" "$C_GRAY"
        return 0
    fi

    error "Integrity chain: INVALID"
    if [[ -n "$LOGGER_CHAIN_FAIL_REASON" ]]; then
        hint "Reason: $LOGGER_CHAIN_FAIL_REASON"
    fi
    if (( LOGGER_CHAIN_FAIL_EVENT > 0 )); then
        hint "Failed at event: $LOGGER_CHAIN_FAIL_EVENT"
    fi
    return 1
}