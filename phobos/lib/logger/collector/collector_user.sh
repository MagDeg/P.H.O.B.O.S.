#!/bin/bash

# collect user/group management events from journal messages.
# recognized lines (tool-name prefixes as emitted by useradd/usermod/...):
#   useradd[pid]: new user: name=<user>, UID=..., GID=..., home=..., shell=...
#   userdel[pid]: delete user '<user>'   (also "removed user '<user>'")
#   usermod[pid]: change user '<user>' ...
#   chsh[pid]: ... user '<user>' ...  / chfn[pid]: ... user '<user>' ...
#   passwd[pid]: pam_unix(passwd:chauthtok): password changed for <user>
#   groupadd[pid]: group added to /etc/group: name=<group>, GID=...
#   gpasswd[pid]: user <user> added to group <group>
#   groupdel[pid]: group '<group>' removed
logger_collect_user() {
    local line="$1"
    local user_name=""
    local group_name=""
    local details=""
    
    # regexes with literal quotes are kept in variables: a bare `'` would
    # otherwise open a shell quote inside the [[ =~ ]] expression.
    local re_userdel="userdel\[[0-9]+\]:[[:space:]]*(delete|removed)[[:space:]]+user[[:space:]]+[']([^']+)[']"
    local re_usermod="usermod\[[0-9]+\]:[[:space:]]+change[[:space:]]+user[[:space:]]+[']([^']+)[']"
    local re_chsh="ch(sh|fn)\[[0-9]+\]:.*user[[:space:]]+[']([^']+)[']"
    local re_groupdel="groupdel\[[0-9]+\]:[[:space:]]*group[[:space:]]+[']([^']+)['][[:space:]]+removed"

    # if line is empty
    [[ -n "$line" ]] || return 1

    # useradd[pid]: new user: name=<user>, UID=..., GID=..., home=..., shell=...
    if [[ "$line" =~ useradd\[[0-9]+\]:[[:space:]]+new[[:space:]]+user:[[:space:]]+name=([^,[:space:]]+) ]]; then
        user_name="${BASH_REMATCH[1]}"

        # collect optional metadata for the details field
        details="tool=useradd"
        [[ "$line" =~ UID=([0-9]+) ]] && details+=" uid=${BASH_REMATCH[1]}"
        [[ "$line" =~ GID=([0-9]+) ]] && details+=" gid=${BASH_REMATCH[1]}"
        [[ "$line" =~ home=([^,[:space:]]+) ]] && details+=" home=${BASH_REMATCH[1]}"
        [[ "$line" =~ shell=([^,[:space:]]+) ]] && details+=" shell=${BASH_REMATCH[1]}"

        logger_event \
            "USER" \
            "USER_CREATED" \
            "SYSTEM" \
            "SUCCESS" \
            "MEDIUM" \
            --source "local" \
            --target "user:$user_name" \
            --details "$details"
        return 0
    fi

    # userdel[pid]: delete user '<user>'  /  removed user '<user>'
    if [[ "$line" =~ $re_userdel ]]; then
        user_name="${BASH_REMATCH[2]}"

        logger_event \
            "USER" \
            "USER_DELETED" \
            "SYSTEM" \
            "SUCCESS" \
            "HIGH" \
            --source "local" \
            --target "user:$user_name" \
            --details "tool=userdel"
        return 0
    fi

    # usermod[pid]: change user '<user>' ...
    if [[ "$line" =~ $re_usermod ]]; then
        user_name="${BASH_REMATCH[1]}"

        logger_event \
            "USER" \
            "USER_MODIFIED" \
            "SYSTEM" \
            "SUCCESS" \
            "MEDIUM" \
            --source "local" \
            --target "user:$user_name" \
            --details "tool=usermod"
        return 0
    fi

    # chsh[pid]: ... user '<user>' ...  /  chfn[pid]: ... user '<user>' ...
    if [[ "$line" =~ $re_chsh ]]; then
        user_name="${BASH_REMATCH[2]}"

        logger_event \
            "USER" \
            "USER_MODIFIED" \
            "SYSTEM" \
            "SUCCESS" \
            "MEDIUM" \
            --source "local" \
            --target "user:$user_name" \
            --details "tool=ch${BASH_REMATCH[1]}"
        return 0
    fi

    # passwd[pid]: pam_unix(passwd:chauthtok): password changed for <user>
    if [[ "$line" =~ passwd\[[0-9]+\]:.*password[[:space:]]+changed[[:space:]]+for[[:space:]]+([^[:space:]]+) ]]; then
        user_name="${BASH_REMATCH[1]}"

        logger_event \
            "USER" \
            "USER_MODIFIED" \
            "SYSTEM" \
            "SUCCESS" \
            "HIGH" \
            --source "local" \
            --target "user:$user_name" \
            --details "tool=passwd change=password"
        return 0
    fi

    # groupadd[pid]: group added to /etc/group: name=<group>, GID=...
    if [[ "$line" =~ groupadd\[[0-9]+\]:.*name=([^,[:space:]]+) ]]; then
        group_name="${BASH_REMATCH[1]}"

        details="tool=groupadd"
        [[ "$line" =~ GID=([0-9]+) ]] && details+=" gid=${BASH_REMATCH[1]}"

        logger_event \
            "USER" \
            "GROUP_ADDED" \
            "SYSTEM" \
            "SUCCESS" \
            "MEDIUM" \
            --source "local" \
            --target "group:$group_name" \
            --details "$details"
        return 0
    fi

    # gpasswd[pid]: user <user> added to group <group>
    if [[ "$line" =~ gpasswd\[[0-9]+\]:[[:space:]]+user[[:space:]]+([^[:space:]]+)[[:space:]]+added[[:space:]]+to[[:space:]]+group[[:space:]]+([^[:space:]]+) ]]; then
        user_name="${BASH_REMATCH[1]}"
        group_name="${BASH_REMATCH[2]}"

        logger_event \
            "USER" \
            "GROUP_ADDED" \
            "SYSTEM" \
            "SUCCESS" \
            "MEDIUM" \
            --source "local" \
            --target "group:$group_name" \
            --details "tool=gpasswd user=$user_name"
        return 0
    fi

    # gpasswd[pid]: user <user> removed from group <group>
    if [[ "$line" =~ gpasswd\[[0-9]+\]:[[:space:]]+user[[:space:]]+([^[:space:]]+)[[:space:]]+removed[[:space:]]+from[[:space:]]+group[[:space:]]+([^[:space:]]+) ]]; then
        user_name="${BASH_REMATCH[1]}"
        group_name="${BASH_REMATCH[2]}"

        logger_event \
            "USER" \
            "GROUP_REMOVED" \
            "SYSTEM" \
            "SUCCESS" \
            "MEDIUM" \
            --source "local" \
            --target "group:$group_name" \
            --details "tool=gpasswd user=$user_name"
        return 0
    fi

    # groupdel[pid]: group '<group>' removed
    if [[ "$line" =~ $re_groupdel ]]; then
        group_name="${BASH_REMATCH[1]}"

        logger_event \
            "USER" \
            "GROUP_REMOVED" \
            "SYSTEM" \
            "SUCCESS" \
            "MEDIUM" \
            --source "local" \
            --target "group:$group_name" \
            --details "tool=groupdel"
        return 0
    fi

    return 1
}
