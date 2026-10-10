#!/bin/bash

logger_collect_drive() {
    local action="$1"
    local device="$2"
    local label="$3"
    local filesystem="$4"

    if [[ -z "$action" ]]; then
        echo "Drive action is required."
        return 1
    fi

    if [[ -z "$device" ]]; then
        echo "Drive device is required."
        return 1
    fi

    case "$action" in
        add)
            action="CONNECT"
            ;;
        remove)
            action="DISCONNECT"
            ;;
        *)
            echo "Invalid drive action: $action"
            return 1
            ;;
    esac

    [[ -n "$label" ]] || label="-"
    [[ -n "$filesystem" ]] || filesystem="-"

    logger_event \
        "DRIVE" \
        "$action" \
        "SYSTEM" \
        "SUCCESS" \
        "MEDIUM" \
        --source "$device" \
        --device "$label" \
        --details "filesystem=$filesystem"
}

logger_collect_udev() {
    if [[ "$SUBSYSTEM" != "block" ]]; then
        return 0
    fi

    case "$ACTION" in
        add)
            logger_collect_drive \
                "add" \
                "$DEVNAME" \
                "$ID_FS_LABEL" \
                "$ID_FS_TYPE"
            ;;
        remove)
            logger_collect_drive \
                "remove" \
                "$DEVNAME" \
                "$ID_FS_LABEL" \
                "$ID_FS_TYPE"
            ;;
        *)
            return 0
            ;;
    esac
}