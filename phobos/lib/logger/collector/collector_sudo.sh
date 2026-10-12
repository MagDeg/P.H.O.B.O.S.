#!/bin/bash


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
