#!/bin/bash 


# defining path to directory, where logger shall store relevant actions
LOGGER_DIR="/var/lib/phobos/logger"
# single event file 
EVENT_LOG="$LOGGER_DIR/events.log"
# file to store previous hash value for generation of next hash
LOGGER_CHAIN_FILE="$LOGGER_DIR/chain.hash"

logger_storage_init() {
    mkdir -p "$LOGGER_DIR" || {
        echo "Logger storage initialization failed."
        return 1
    }

    chmod 700 "$LOGGER_DIR" || {
        echo "Failed to secure logger directory."
        return 1
    }

    touch "$EVENT_LOG" || {
        echo "Failed to create event log."
        return 1
    }

    chmod 600 "$EVENT_LOG" || {
        echo "Failed to secure event log."
        return 1
    }

    touch "$LOGGER_CHAIN_FILE" || {
        echo "Failed to create chain file."
        return 1
    }

    chmod 600 "$LOGGER_CHAIN_FILE" || {
        echo "Failed to secure chain file."
        return 1
    }

    return 0
}

logger_store_event() {
    local event="$1"

    if ! logger_storage_init; then
        echo "Logger storage initialization failed."
        return 1
    fi

    local previous_hash=""

    if [[ -f "$LOGGER_CHAIN_FILE" ]]; then
        previous_hash=$(cat "$LOGGER_CHAIN_FILE")
    fi

    local event_hash
    event_hash=$(printf '%s%s' "$previous_hash" "$event" |
        sha256sum |
        awk '{print $1}')

    {
        printf '%s\n' "$event"
        printf 'event_hash=%s\n' "$event_hash"
        printf '%s\n' "---"
    } >> "$EVENT_LOG" || {
        echo "Failed to write logger event."
        return 1
    }

    printf '%s\n' "$event_hash" > "$LOGGER_CHAIN_FILE" || {
        echo "Failed to update logger chain."
        return 1
    }
}

logger_verify_chain() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "This command requires root privileges."
        echo "Run: sudo phobos logger verify"
        return 1
    fi

    if [[ ! -f "$EVENT_LOG" ]]; then
        echo "Event log not found."
        return 1
    fi

    if [[ ! -f "$LOGGER_CHAIN_FILE" ]]; then
        echo "Chain file not found."
        return 1
    fi

    local previous_hash=""
    local event=""
    local stored_hash=""
    local calculated_hash=""
    local event_count=0
    local line

    while IFS= read -r line; do

        if [[ "$line" == "---" ]]; then

            calculated_hash=$(printf '%s%s' "$previous_hash" "$event" |
                sha256sum |
                awk '{print $1}')

            if [[ "$calculated_hash" != "$stored_hash" ]]; then
                echo "Integrity chain: INVALID"
                echo "Failed at event: $((event_count + 1))"
                echo "Reason: event hash mismatch"
                return 1
            fi

            previous_hash="$stored_hash"
            event=""
            stored_hash=""
            ((event_count++))

        elif [[ "$line" == event_hash=* ]]; then
            stored_hash="${line#event_hash=}"

        else
            if [[ -n "$event" ]]; then
                event+=$'\n'
            fi

            event+="$line"
        fi

    done < "$EVENT_LOG"

    local chain_hash
    chain_hash=$(cat "$LOGGER_CHAIN_FILE")

    if [[ "$previous_hash" != "$chain_hash" ]]; then
        echo "Integrity chain: INVALID"
        echo "Reason: final chain hash mismatch"
        return 1
    fi

    echo "PHOBOS Logger Integrity"
    echo "-----------------------"
    echo "Events checked: $event_count"
    echo "Chain status:   VALID"
    echo "Final hash:     $chain_hash"

    return 0
}