#!/bin/bash


logger_collect_drive() {
    local action="$1"
    local device="$2"
    local label="$3"
    local filesystem="$4"

    # action is a mandatory parameter
    if [[ -z "$action" ]]; then
        logger_error "Drive action is required."
        return 1
    fi

    # device is a mandatory parameter
    if [[ -z "$device" ]]; then
        logger_error "Drive device is required."
        return 1
    fi

    # mapping add -> CONNECT, remove -> DISCONNECT
    case "$action" in
        add)
            action="CONNECT"
            ;;
        remove)
            action="DISCONNECT"
            ;;
        *)
            logger_error "Invalid drive action: $action"
            return 1
            ;;
    esac

    # setting default to empty optional parameters
    [[ -n "$label" ]] || label="-"
    [[ -n "$filesystem" ]] || filesystem="-"

    # generating a logger_event
    # note: user=SYSTEM because events system-generated
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
    # $SUBSYSTEM is udev environment variable
    # when udev/kernel triggers event, it tags it with kernel subsystem the device belongs to
    # "block" -> everything that has sth. to do with storage such like partitions, usb, harddrives etc.
    if [[ "${SUBSYSTEM:-}" != "block" ]]; then
        return 0
    fi

    # depending on $ACTION different events are created
    # used env vars are set by udev
    case "${ACTION:-}" in
        add)
            logger_collect_drive \
                "add" \
                "${DEVNAME:-}" \
                "${ID_FS_LABEL:-}" \
                "${ID_FS_TYPE:-}"
            return $?
            ;;
        remove)
            logger_collect_drive \
                "remove" \
                "${DEVNAME:-}" \
                "${ID_FS_LABEL:-}" \
                "${ID_FS_TYPE:-}"
            return $?
            ;;
        *)
            return 0
            ;;
    esac
}
