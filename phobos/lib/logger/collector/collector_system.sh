#!/bin/bash

# collect system-level events (boot/shutdown/reboot, systemd units, reloads)
# from journal messages. All events are attributed to the SYSTEM pseudo-user.
# recognized lines:
#   systemd[1]: Startup finished in ...
#   systemd[1]: Shutting down.
#   systemd[1]: Rebooting.  /  systemd-shutdown[1]: Rebooting.
#   systemd[1]: Started <unit>.
#   systemd[1]: Stopped <unit>.
#   systemd[1]: Reloading.  /  systemd[1]: Reloaded <unit>.
logger_collect_system() {
    local line="$1"
    local unit=""

    # if line is empty
    [[ -n "$line" ]] || return 1

    # systemd[1]: Startup finished in ...
    if [[ "$line" =~ systemd\[[0-9]+\]:[[:space:]]+Startup[[:space:]]+finished ]]; then
        logger_event \
            "SYSTEM" \
            "BOOT" \
            "SYSTEM" \
            "SUCCESS" \
            "INFO" \
            --source "systemd" \
            --details "event=startup_finished"
        return 0
    fi

    # systemd[1]: Shutting down.  /  systemd-shutdown[1]: ... Power off ...
    if [[ "$line" =~ systemd\[[0-9]+\]:[[:space:]]+Shutting[[:space:]]+down ]] ||
       [[ "$line" =~ systemd-shutdown\[[0-9]+\]:.*Power[[:space:]]+off ]]; then
        logger_event \
            "SYSTEM" \
            "SHUTDOWN" \
            "SYSTEM" \
            "SUCCESS" \
            "LOW" \
            --source "systemd" \
            --details "event=shutdown"
        return 0
    fi

    # systemd[1]: Rebooting.  /  systemd-shutdown[1]: ... Rebooting ...
    if [[ "$line" =~ systemd\[[0-9]+\]:[[:space:]]+Rebooting ]] ||
       [[ "$line" =~ systemd-shutdown\[[0-9]+\]:.*Rebooting ]]; then
        logger_event \
            "SYSTEM" \
            "REBOOT" \
            "SYSTEM" \
            "SUCCESS" \
            "LOW" \
            --source "systemd" \
            --details "event=reboot"
        return 0
    fi

    # systemd[1]: Started <unit>.
    if [[ "$line" =~ systemd\[[0-9]+\]:[[:space:]]+Started[[:space:]]+(.+)\.[[:space:]]*$ ]]; then
        unit="${BASH_REMATCH[1]}"

        logger_event \
            "SYSTEM" \
            "SERVICE_STARTED" \
            "SYSTEM" \
            "SUCCESS" \
            "LOW" \
            --source "systemd" \
            --target "$unit" \
            --details "unit=$unit"
        return 0
    fi

    # systemd[1]: Stopped <unit>.
    if [[ "$line" =~ systemd\[[0-9]+\]:[[:space:]]+Stopped[[:space:]]+(.+)\.[[:space:]]*$ ]]; then
        unit="${BASH_REMATCH[1]}"

        logger_event \
            "SYSTEM" \
            "SERVICE_STOPPED" \
            "SYSTEM" \
            "SUCCESS" \
            "LOW" \
            --source "systemd" \
            --target "$unit" \
            --details "unit=$unit"
        return 0
    fi

    # systemd[1]: Failed to start <unit>.
    if [[ "$line" =~ systemd\[[0-9]+\]:[[:space:]]+Failed[[:space:]]+to[[:space:]]+start[[:space:]]+(.+)\.[[:space:]]*$ ]]; then
        unit="${BASH_REMATCH[1]}"

        logger_event \
            "SYSTEM" \
            "SERVICE_STARTED" \
            "SYSTEM" \
            "FAILED" \
            "MEDIUM" \
            --source "systemd" \
            --target "$unit" \
            --details "unit=$unit failed_to_start"
        return 0
    fi

    # systemd[1]: Reloading.  /  systemd[1]: Reloaded <unit>.
    if [[ "$line" =~ systemd\[[0-9]+\]:[[:space:]]+Reload(ing|ed)[[:space:]]*(.*)$ ]]; then
        unit="${BASH_REMATCH[2]}"
        # strip a trailing period so bare "Reloading." yields no unit
        unit="${unit%.}"

        logger_event \
            "SYSTEM" \
            "CONFIG_CHANGED" \
            "SYSTEM" \
            "SUCCESS" \
            "LOW" \
            --source "systemd" \
            --target "${unit:--}" \
            --details "event=reload unit=${unit:--}"
        return 0
    fi

    return 1
}
