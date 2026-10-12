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

# collect authentication events from journal messages.
# recognized lines (pam_unix service names cover lightdm, sshd, login/tty, ...):
#   pam_unix(<service>:session): session opened|closed for user <user>
#   pam_unix(<service>:auth): authentication failure ... user=<user>
#   sshd[<pid>]: Invalid user <user> from <ip>
#   sshd[<pid>]: Failed password for invalid user <user> from <ip>
logger_collect_auth() {
    local line="$1"
    local auth_user=""
    local auth_source=""
    local auth_service=""
    local auth_ip=""

    # if line is empty
    [[ -n "$line" ]] || return 1

    # pam_unix(<service>:session): session opened for user <user>
    if [[ "$line" =~ pam_unix\(([^:]+):session\):[[:space:]]session\ opened\ for\ user[[:space:]]+([^[:space:]]+) ]]; then
        # BASH_REMATCH[1] = service, BASH_REMATCH[2] = user
        auth_service="${BASH_REMATCH[1]}"
        auth_user="${BASH_REMATCH[2]}"

        # sudo sessions are handled by the sudo collector, so they are skipped here 
        [[ "$auth_service" == "sudo" ]] && return 1
        auth_source="$auth_service"

        logger_event \
            "AUTH" \
            "LOGIN_SUCCESS" \
            "$auth_user" \
            "SUCCESS" \
            "MEDIUM" \
            --source "$auth_source" \
            --details "event=session_opened"
        return 0
    fi

    # pam_unix(<service>:session): session closed for user <user>
    if [[ "$line" =~ pam_unix\(([^:]+):session\):[[:space:]]session\ closed\ for\ user[[:space:]]+([^[:space:]]+) ]]; then
        auth_service="${BASH_REMATCH[1]}"
        auth_user="${BASH_REMATCH[2]}"

        [[ "$auth_service" == "sudo" ]] && return 1
        auth_source="$auth_service"

        logger_event \
            "AUTH" \
            "LOGOUT" \
            "$auth_user" \
            "SUCCESS" \
            "LOW" \
            --source "$auth_source" \
            --details "event=session_closed"
        return 0
    fi

    # pam_unix(<service>:auth): authentication failure ... user=<user>
    if [[ "$line" =~ pam_unix\(([^:]+):auth\):.*authentication\ failure ]]; then
        auth_service="${BASH_REMATCH[1]}"

        [[ "$auth_service" == "sudo" ]] && return 1
        auth_source="$auth_service"

        # extract user if present, otherwise mark as UNKNOWN
        if [[ "$line" =~ user=([^[:space:]]+) ]]; then
            auth_user="${BASH_REMATCH[1]}"
        else
            auth_user="UNKNOWN"
        fi

        logger_event \
            "AUTH" \
            "LOGIN_FAILED" \
            "$auth_user" \
            "FAILED" \
            "HIGH" \
            --source "$auth_source" \
            --details "event=pam_authentication_failure"
        return 0
    fi

    # sshd[<pid>]: Invalid user <user> from <ip>
    if [[ "$line" =~ sshd\[[0-9]+\]:[[:space:]]Invalid\ user[[:space:]]+([^[:space:]]+)[[:space:]]+from[[:space:]]+([^[:space:]]+) ]]; then
        auth_user="${BASH_REMATCH[1]}"
        auth_ip="${BASH_REMATCH[2]}"

        logger_event \
            "AUTH" \
            "LOGIN_FAILED" \
            "$auth_user" \
            "FAILED" \
            "HIGH" \
            --source "ssh" \
            --details "event=invalid_user ip=$auth_ip"
        return 0
    fi

    # sshd[<pid>]: Failed password for invalid user <user> from <ip>
    if [[ "$line" =~ sshd\[[0-9]+\]:[[:space:]]Failed\ password\ for\ invalid\ user[[:space:]]+([^[:space:]]+)[[:space:]]+from[[:space:]]+([^[:space:]]+) ]]; then
        auth_user="${BASH_REMATCH[1]}"
        auth_ip="${BASH_REMATCH[2]}"

        logger_event \
            "AUTH" \
            "LOGIN_FAILED" \
            "$auth_user" \
            "FAILED" \
            "HIGH" \
            --source "ssh" \
            --details "event=invalid_password ip=$auth_ip"
        return 0
    fi

    return 1
}


# collect sudo command and authentication events from journal messages.
logger_collect_sudo() {
    local line="$1"
    local sudo_user=""
    local target_user="root"
    local details=""

    # if line is empty
    [[ -n "$line" ]] || return 1

    # detect prohobited sudo-calls FIRST: denial lines also carry COMMAND=,
    # so they would otherwise match the success pattern below.
    # handles both classic "sudo:" and journald "sudo[pid]:" prefixes.
    if [[ "$line" =~ sudo(\[[0-9]+\])?:.*(not\ in\ the\ sudoers|NOT\ in\ sudoers|command\ not\ allowed) ]]; then
        # extracting user from message
        # if user can be extracted
        if [[ "$line" =~ sudo(\[[0-9]+\])?:[[:space:]]*([^[:space:]]+)[[:space:]]*: ]]; then
            sudo_user="${BASH_REMATCH[2]}"
        # if no user can be extracted, set to UNKNOWN
        else
            sudo_user="UNKNOWN"
        fi

        # generating new event
        logger_event \
            "AUTH" \
            "SUDO_FAILED" \
            "$sudo_user" \
            "DENIED" \
            "HIGH" \
            --source "sudo" \
            --details "event=sudo_authorization_denied"
        return 0
    fi

    # detect successfull sudo-auths
    # searches messages like: Oct 12 14:00 host sudo[1234]: <user> : TTY=pts/0 ; USER=root ; COMMAND=/usr/bin/apt update
    if [[ "$line" =~ sudo(\[[0-9]+\])?:[[:space:]]*([^[:space:]]+)[[:space:]]*:.*COMMAND=(.*)$ ]]; then
        # storing capture groups to local variables
        sudo_user="${BASH_REMATCH[2]}" # calling user
        details="${BASH_REMATCH[3]}" # command and additional characters

        # getting target_user
        # searching for USER= and extracting following word
        if [[ "$line" =~ USER=([^[:space:]\;]+) ]]; then
            target_user="${BASH_REMATCH[1]}"
        fi

        # generating new event
        logger_event \
            "AUTH" \
            "SUDO_SUCCESS" \
            "$sudo_user" \
            "SUCCESS" \
            "MEDIUM" \
            --source "sudo" \
            --target "$target_user" \
            --details "command=$details"
        return 0
    fi

    # detect failed sudo-auths
    # searces messages like: pam_unix(sudo:auth): authentication failure; user=<user>
    if [[ "$line" =~ pam_unix\(sudo:auth\):.*authentication\ failure ]]; then
        # extracting user from line
        # if a user can be extracted
        if [[ "$line" =~ user=([^[:space:]]+) ]]; then
            sudo_user="${BASH_REMATCH[1]}"
        # if no user can be extracted, set to UNKNOWN
        else
            sudo_user="UNKNOWN"
        fi

        # generating new event
        logger_event \
            "AUTH" \
            "SUDO_FAILED" \
            "$sudo_user" \
            "FAILED" \
            "HIGH" \
            --source "sudo" \
            --details "event=pam_authentication_failure"
        return 0
    fi

    return 1
}


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
