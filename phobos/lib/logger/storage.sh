#!/bin/bash

# if LOGGER_DIR is unset/empty, set default; := makes it overridable 
: "${LOGGER_DIR:=/var/lib/phobos/logger}"
readonly LOGGER_DIR
readonly EVENT_LOG="$LOGGER_DIR/events.log"
readonly LOGGER_CHAIN_FILE="$LOGGER_DIR/chain.hash"
readonly LOGGER_NET_STATE_DIR="$LOGGER_DIR/net"  # [NEW] per-interface byte baselines

# udev integration paths (used by lifecycle.sh).
readonly LOGGER_UDEV_RULES="/etc/udev/rules.d/98-phobos-logger.rules"
readonly LOGGER_UDEV_HELPER="${LIB_DIR:-/usr/local/lib/phobos}/logger/logger_udev.sh"

# journal integration paths (used by lifecycle.sh).
readonly LOGGER_JOURNAL_UNIT="/etc/systemd/system/phobos-logger-journal.service"
readonly LOGGER_JOURNAL_HELPER="${LIB_DIR:-/usr/local/lib/phobos}/logger/logger_journal.sh"

# file-operation (auditd) integration paths (used by lifecycle.sh).  
readonly LOGGER_AUDIT_RULES="/etc/audit/rules.d/50-phobos-file.rules"  # where logger enable writes audit rules
readonly LOGGER_AUDIT_UNIT="/etc/systemd/system/phobos-logger-audit.service" # path of systemd unit that streams audot records into logger
readonly LOGGER_AUDIT_HELPER="${LIB_DIR:-/usr/local/lib/phobos}/logger/logger_audit.sh" #absolute path of entry point logger_audit.sh
readonly LOGGER_AUDIT_LOG="/var/log/audit/audit.log" #raw auditd log the collector streams (tail -F)  # [NEW]

# permission/ownership/ACL audit rules (separate key from file rules).
readonly LOGGER_PERMISSION_RULES="/etc/audit/rules.d/51-phobos-permission.rules"

logger_storage_init() {
    # creating diredctory for logger file
    # || on error, do {...}
    mkdir -p "$LOGGER_DIR" || {
        logger_error "Logger storage initialization failed."
        return 1
    }

    # make dir private, so only owner can read, write, execute
    chmod 700 "$LOGGER_DIR" || {
        logger_error "Failed to secure logger directory."
        return 1
    }

    # creating log-file
    touch "$EVENT_LOG" || {
        logger_error "Failed to create event log."
        return 1
    }

    # make file private, so only owner can read, write
    chmod 600 "$EVENT_LOG" || {
        logger_error "Failed to secure event log."
        return 1
    }

    # creating file for chain-hash
    touch "$LOGGER_CHAIN_FILE" || {
        logger_error "Failed to create chain file."
        return 1
    }

    # make file private, so only owner can read, write
    chmod 600 "$LOGGER_CHAIN_FILE" || {
        logger_error "Failed to secure chain file."
        return 1
    }

    # per-interface network state directory (byte-counter baselines)
    mkdir -p "$LOGGER_NET_STATE_DIR" || {
        logger_error "Failed to create network state directory."
        return 1
    }

    # make dir private, so only owner can read, write, execute
    chmod 700 "$LOGGER_NET_STATE_DIR" || {
        logger_error "Failed to secure network state directory."
        return 1
    }

    return 0
}

# appends one validated event to log-file and advances hash-chain.
logger_store_event() {
    # variable for event
    # will be given as multiline string
    local event="$1"

    # making shure all relevant files exist, on error return 1
    logger_storage_init || return 1

    local previous_hash=""
    # reading hash-file to get previous hash, if it exists
    if [[ -f "$LOGGER_CHAIN_FILE" ]]; then
        # $(...) strips trailing newline
        previous_hash=$(cat "$LOGGER_CHAIN_FILE")
    fi

    local event_hash
    # generating new hash with previous hash and event
    # awk extracts only hash
    event_hash=$(printf '%s%s' "$previous_hash" "$event" |
        sha256sum |
        awk '{print $1}')

    # writing values into log-file
    {
        #writing event into log-file
        printf '%s\n' "$event"
        # appending hash-value
        printf 'event_hash=%s\n' "$event_hash"
        # adding seperator, for easy extracting of events
        printf -- '---\n'
    } >> "$EVENT_LOG" || {
        # on error: 
        logger_error "Failed to write logger event."
        return 1
    }

    # overwriting (>) hash-file
    printf '%s\n' "$event_hash" > "$LOGGER_CHAIN_FILE" || {
        logger_error "Failed to update logger chain."
        return 1
    }

    return 0
}


# simply walks through events and uses given callback function on each event
logger_chain_walk() {
    local logfile="$1"
    local callback="$2"
    local line
    local event=""
    local stored_hash=""

    # reading log file line by line
    while IFS= read -r line; do
        # if seperator reached
        if [[ "$line" == "---" ]]; then
            # setting global variables
            # Note: assigning a name without keyword local in bash, creates shell-global variable
            LOGGER_EVENT_BODY="$event"
            LOGGER_EVENT_HASH="$stored_hash"

            # calling "$callback"
            # if it returns non-zero, return $? stops iteration and propagates that status
            "$callback" || return $?

            # resetting local variables
            event=""
            stored_hash=""
        # if line starts with event_hash
        elif [[ "$line" == event_hash=* ]]; then
            # string line into variable (stripped of prefix)
            stored_hash="${line#event_hash=}"
        # if line is inside of event entry
        else
            # if event is not empty, prefixing newline
            if [[ -n "$event" ]]; then
                event+=$'\n'
            fi
            # if event is empty, simply adding line
            event+="$line"
        fi
    done < "$logfile"

    return 0
}

# callback for logger_chain_check(): recomputes hash for one event and
# compares it with stored one
_logger_chain_check_event() {
    local calculated_hash
    # calculating hash from previous hash and event
    # note: for the first event hash is calculates by using "" and the event itself
    calculated_hash=$(printf '%s%s' "${_LOGGER_PREVIOUS_HASH:-}" "$LOGGER_EVENT_BODY" |
        sha256sum |
        awk '{print $1}')

    # if calculated hash is different, from written hash in file
    if [[ "$calculated_hash" != "$LOGGER_EVENT_HASH" ]]; then
        # setting number of event that failed
        LOGGER_CHAIN_FAIL_EVENT=$((LOGGER_CHAIN_EVENTS + 1))
        # setting fail reason
        LOGGER_CHAIN_FAIL_REASON="event hash mismatch"
        return 1
    fi

    # setting local variable to hash-value from file
    _LOGGER_PREVIOUS_HASH="$LOGGER_EVENT_HASH"
    # incrementing number of looked events
    ((LOGGER_CHAIN_EVENTS++))
    return 0
}

# verifies whole chain
# returns 0 when intact, 1 otherwise.
# result details are exposed via:
#   LOGGER_CHAIN_EVENTS     number of events verified
#   LOGGER_CHAIN_HASH       final hash read from the chain file
#   LOGGER_CHAIN_FAIL_EVENT 1-based index of the failing event (0 if none)
#   LOGGER_CHAIN_FAIL_REASON human readable failure reason
logger_chain_check() {
    # resetting global variables
    LOGGER_CHAIN_EVENTS=0
    LOGGER_CHAIN_HASH=""
    LOGGER_CHAIN_FAIL_EVENT=0
    LOGGER_CHAIN_FAIL_REASON=""

    # if log-file does not exist
    if [[ ! -f "$EVENT_LOG" ]]; then
        logger_error "Event log not found."
        return 1
    fi

    # if chain-file does not exist
    if [[ ! -f "$LOGGER_CHAIN_FILE" ]]; then
        logger_error "Chain file not found."
        return 1
    fi

    # initialising previous hash var for chain walk
    _LOGGER_PREVIOUS_HASH=""

    # iterating over chain, with check_event as callback
    logger_chain_walk "$EVENT_LOG" _logger_chain_check_event || return 1

    # tip of the recomputed chain must match stored chain file,
    # otherwise the log was truncated or had events appended/removed.
    LOGGER_CHAIN_HASH=$(cat "$LOGGER_CHAIN_FILE")
    if [[ "$_LOGGER_PREVIOUS_HASH" != "$LOGGER_CHAIN_HASH" ]]; then
        LOGGER_CHAIN_FAIL_REASON="final chain hash mismatch"
        return 1
    fi

    return 0
}

logger_delete_records() {
    logger_require_root "logger clear" || return 1


    # deletion of chain file
    if [[ -f "$LOGGER_CHAIN_FILE" ]]; then
        rm -f "$LOGGER_CHAIN_FILE"
        echo "Removed logger chain-file"
    else
        logger_error "No logger chain-file found"
    fi
    # deletion of log file
    if [[ -f "$EVENT_LOG" ]]; then 
        rm -f "$EVENT_LOG"
        echo "Removed logger log-file"
    else
        logger_error "No logger log-file found"
    fi
    echo "Deletion of logger files finished"
    return 0
}
