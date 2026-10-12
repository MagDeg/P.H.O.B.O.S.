#!/bin/bash


# category -> space separated list of allowed actions.
# declare -A ... creates associative array 
declare -A LOGGER_ACTIONS=(
    [FILE]="CREATE COPY MOVE DELETE MODIFY RENAME READ WRITE"
    [DRIVE]="CONNECT DISCONNECT MOUNT UNMOUNT"
    [AUTH]="LOGIN_SUCCESS LOGIN_FAILED LOGOUT SUDO_SUCCESS SUDO_FAILED"
    [USER]="USER_CREATED USER_DELETED USER_MODIFIED GROUP_ADDED GROUP_REMOVED"
    [PERMISSION]="PERMISSION_CHANGED OWNER_CHANGED ACL_CHANGED"
    [PROCESS]="START STOP CRASH"
    [NETWORK]="CONNECTION DISCONNECTION"
    [SYSTEM]="BOOT SHUTDOWN REBOOT SERVICE_STARTED SERVICE_STOPPED CONFIG_CHANGED"
    [SECURITY]="ANOMALY_DETECTED INTEGRITY_FAILURE TAMPERING_DETECTED SUSPICIOUS_ACTIVITY"
)

# status -> 1 (used as a set).
declare -A LOGGER_STATUSES=(
    [SUCCESS]=1
    [FAILED]=1
    [DENIED]=1
)

# severity -> 1 (used as a set).
declare -A LOGGER_SEVERITIES=(
    [INFO]=1
    [LOW]=1
    [MEDIUM]=1
    [HIGH]=1
    [CRITICAL]=1
)

# like a const variable
readonly -A LOGGER_ACTIONS LOGGER_STATUSES LOGGER_SEVERITIES


# returns 0 when $1 is a known category.
logger_validate_category() {
    # $1 used as key in LOGGER_ACTIONS
    # :- makes missing key expand into -, instead if erroring
    # -n : if string is not empty
    [[ -n "${LOGGER_ACTIONS[$1]:-}" ]]
}

# returns 0 when $2 is allowed for category $1.
logger_validate_action() {
    local category="$1"
    local action="$2"

    [[ " ${LOGGER_ACTIONS[$category]:-} " == *" $action "* ]]
}

# returns 0 when $1 is a known status.
logger_validate_status() {
    [[ -n "${LOGGER_STATUSES[$1]:-}" ]]
}

# returns 0 when $1 is a known severity.
logger_validate_severity() {
    [[ -n "${LOGGER_SEVERITIES[$1]:-}" ]]
}

# Ensures none of the five required fields is empty, printing a message for
# the first missing one. Returns 0 only when all are present.
logger_validate_required_fields() {
    local entry
    local name
    local value

    # iterates over 5 strings
    for entry in "category:$1" "action:$2" "user:$3" "status:$4" "severity:$5"; do
        # remove longest suffix matching :* (everything from the forst colon to the end) -> field name
        name="${entry%%:*}"
        # remove shortest prefix through the first colon -> the value
        value="${entry#*:}"

        # if one value is empty, its missing
        if [[ -z "$value" ]]; then
            logger_error "Logger $name is required."
            return 1
        fi
    done

    return 0
}

# emits a unique event id: 16 random bytes rendered as 32 lowercase hex chars.
logger_generate_id() {
    openssl rand -hex 16
}
