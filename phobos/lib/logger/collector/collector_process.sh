#!/bin/bash

# collect process crash events from kernel journal messages.
# START/STOP are intentionally not tracked here: capturing every process
# lifecycle event is extremely noisy and is listed as a future extension in
# EVENT_SPEC.md. Only abnormal terminations are recorded as PROCESS/CRASH.
# recognized lines:
#   kernel: <comm>[<pid>]: segfault at <addr> ip <ip> ...
#   kernel: traps: <comm>[<pid>] general protection fault ...
#   kernel: Out of memory: Killed process <pid> (<comm>) ...
#   kernel: kernel BUG at ...
#   kernel: Unable to handle kernel paging request ...
#   kernel: Kernel panic ...
logger_collect_process() {
    local line="$1"
    local comm=""
    local pid=""
    local severity="HIGH"
    local reason=""
    # regex kept in a variable: a bare `)` inside a bracket class would
    # otherwise terminate the [[ =~ ]] expression.
    local re_oom="Killed[[:space:]]+process[[:space:]]+([0-9]+)[[:space:]]+[(]([^)]+)[)]"

    # if line is empty
    [[ -n "$line" ]] || return 1

    # only kernel messages are considered
    [[ "$line" =~ kernel: ]] || return 1

    # <comm>[<pid>]: segfault at ...
    if [[ "$line" =~ ([^[:space:]:]+)\[([0-9]+)\]:[[:space:]]*segfault ]]; then
        comm="${BASH_REMATCH[1]}"
        pid="${BASH_REMATCH[2]}"
        reason="segfault"
    # traps: <comm>[<pid>] general protection fault ...
    elif [[ "$line" =~ traps:[[:space:]]*([^[:space:]\[]+)\[([0-9]+)\] ]]; then
        comm="${BASH_REMATCH[1]}"
        pid="${BASH_REMATCH[2]}"
        reason="general_protection_fault"
    # Out of memory: Killed process <pid> (<comm>) ...
    elif [[ "$line" =~ $re_oom ]]; then
        pid="${BASH_REMATCH[1]}"
        comm="${BASH_REMATCH[2]}"
        reason="oom_kill"
    # kernel BUG at ...
    elif [[ "$line" =~ kernel[[:space:]]+BUG[[:space:]]+at ]]; then
        reason="kernel_bug"
        severity="CRITICAL"
    # Unable to handle kernel paging request ...
    elif [[ "$line" =~ Unable[[:space:]]+to[[:space:]]+handle[[:space:]]+kernel[[:space:]]+paging[[:space:]]+request ]]; then
        reason="kernel_paging_request"
        severity="CRITICAL"
    # Kernel panic ...
    elif [[ "$line" =~ Kernel[[:space:]]+panic ]]; then
        reason="kernel_panic"
        severity="CRITICAL"
    else
        return 1
    fi

    logger_event \
        "PROCESS" \
        "CRASH" \
        "SYSTEM" \
        "FAILED" \
        "$severity" \
        --source "${comm:--}" \
        --target "${pid:--}" \
        --details "reason=$reason comm=${comm:--} pid=${pid:--}"
    return 0
}
