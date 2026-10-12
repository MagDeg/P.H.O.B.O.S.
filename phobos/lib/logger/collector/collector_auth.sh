#!/bin/bash

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
