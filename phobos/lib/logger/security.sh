#!/bin/bash


# simple functions to validate correct parameter values if category, status and severity
logger_validate_category() {
    case "$1" in
        FILE|DRIVE|AUTH|USER|PERMISSION|PROCESS|NETWORK|SYSTEM|SECURITY)
            return 0
            ;;
        *) 
            return 1
            ;;
    esac
}

logger_validate_status() {
    case "$1" in
        SUCCESS|FAILED|DENIED)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

logger_validate_severity() {
    case "$1" in 
        INFO|LOW|MEDIUM|HIGH|CRITICAL)
            return 0
            ;;
        *) 
            return 1
            ;;
    esac
}

# checking if combined parameters are correct

logger_validate_action() {
    local category="$1"
    local action="$2"

    case "$category" in 
        FILE)
            case "$action" in 
                CREATE|COPY|MOVE|MODIFY|RENAME|READ|WRITE)
                    return 0
                    ;;
            esac
            ;;
        DRIVE)
            case "$action" in
                CONNECT|DISCONNECT|MOUNT|UNMOUNT)
                    return 0
                    ;;
            esac
            ;;

        AUTH)
            case "$action" in
                LOGIN_SUCCESS|LOGIN_FAILED|LOGOUT|SUDO_SUCCESS|SUDO_FAILED)
                    return 0
                    ;;
            esac
            ;;

        USER)
            case "$action" in
                USER_CREATED|USER_DELETED|USER_MODIFIED|GROUP_ADDED|GROUP_REMOVED)
                    return 0
                    ;;
            esac
            ;;

        PERMISSION)
            case "$action" in
                PERMISSION_CHANGED|OWNER_CHANGED|ACL_CHANGED)
                    return 0
                    ;;
            esac
            ;;
        PROCESS)
            case "$action" in
                START|STOP|CRASH)
                    return 0
                    ;;
            esac
            ;;

        NETWORK)
            case "$action" in
                CONNECTION|DISCONNECTION)
                    return 0
                    ;;
            esac
            ;;

        SYSTEM)
            case "$action" in
                BOOT|SHUTDOWN|REBOOT|SERVICE_STARTED|SERVICE_STOPPED|CONFIG_CHANGED)
                    return 0
                    ;;
            esac
            ;;

        SECURITY)
            case "$action" in
                ANOMALY_DETECTED|INTEGRITY_FAILURE|TAMPERING_DETECTED|SUSPICIOUS_ACTIVITY)
                    return 0
                    ;;
            esac
            ;;
    esac

    return 1

}
 
# simply checking if all required fields are not empty
logger_validate_required_fields() {
    local category="$1"
    local action="$2"
    local user="$3"
    local status="$4"
    local severity="$5"

    if [[ -z "$category" ]]; then
        echo "Logger category is required."
        return 1
    fi

    if [[ -z "$action" ]]; then
        echo "Logger action is required."
        return 1
    fi

    if [[ -z "$user" ]]; then
        echo "Logger user is required."
        return 1
    fi

    if [[ -z "$status" ]]; then
        echo "Logger status is required."
        return 1
    fi

    if [[ -z "$severity" ]]; then
        echo "Logger severity is required."
        return 1
    fi

    return 0
}

# creates 16 random bytes 
logger_generate_id() {
    openssl rand -hex 16
}