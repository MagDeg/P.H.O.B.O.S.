#!/bin/bash


# creating path to state-file of one network-interface
_logger_net_state_file() {
    printf '%s/%s' "$LOGGER_NET_STATE_DIR" "$1"
}

# reads one cumulative byte counter from one network-interface (sysfs) (kind = rx|tx).
# RX ... received
# TX ... transmitted
_logger_net_counter() {
    local iface="$1"
    local kind="$2"
    local file="/sys/class/net/$iface/statistics/${kind}_bytes"

    [[ -r "$file" ]] || return 1
    printf '%s' "$(< "$file")"
}

# stores the current rx/tx counters as the baseline for interface $1.
_logger_net_state_save() {
    # name of network-interface
    local iface="$1"
    # receiving counter
    local rx=""
    # sendung counter
    local tx=""

    [[ -n "$iface" && -d "$LOGGER_NET_STATE_DIR" ]] || return 0

    # reading rx/tx counter
    rx="$(_logger_net_counter "$iface" rx)" || return 0
    tx="$(_logger_net_counter "$iface" tx)" || return 0

    [[ -n "$rx" && -n "$tx" ]] || return 0

    # writing tx/rx to state-file
    printf 'rx=%s\ntx=%s\n' "$rx" "$tx" > "$(_logger_net_state_file "$iface")" 2>/dev/null
    return 0
}

# removes the baseline for interface $1 and echoes "rx_delta tx_delta" -> basically calculating network volume
_logger_net_state_diff() {
    local iface="$1"
    # path to state file of interface
    local state_file=""
    # previous counter values
    local base_rx=""
    local base_tx=""
    # current counter values
    local cur_rx=""
    local cur_tx=""
    # variables to read state-file
    local key=""
    local value=""

    # getting path to state-file by interface-name
    state_file="$(_logger_net_state_file "$iface")"
    [[ -f "$state_file" ]] || return 1

    # reading state-file line by line
    while IFS='=' read -r key value; do
        # extracting tx/rx from file
        case "$key" in
            rx) base_rx="$value" ;;
            tx) base_tx="$value" ;;
        esac
    done < "$state_file"

    # removing state file
    rm -f "$state_file" 2>/dev/null

    # reading current counter values
    cur_rx="$(_logger_net_counter "$iface" rx)" || cur_rx=""
    cur_tx="$(_logger_net_counter "$iface" tx)" || cur_tx=""

    # calculating rx delta
    if [[ -n "$base_rx" && -n "$cur_rx" && "$cur_rx" -ge "$base_rx" ]]; then
        printf 'rx=%s ' "$((cur_rx - base_rx))"
    fi
    # calculating tx delta
    if [[ -n "$base_tx" && -n "$cur_tx" && "$cur_tx" -ge "$base_tx" ]]; then
        printf 'tx=%s' "$((cur_tx - base_tx))"
    fi
    printf '\n'
    return 0
}

# collect network link events from journal messages.
#   NetworkManager:  device (<iface>): Activation: (<type>) connection '<ssid>' ...
#   NetworkManager:  device (<iface>): state change: activated|disconnected|...
#   wpa_supplicant:  <iface>: CTRL-EVENT-CONNECTED - Connection to <bssid> ...
#   wpa_supplicant:  <iface>: CTRL-EVENT-DISCONNECTED bssid=<bssid> reason=...
#   systemd-networkd:<iface>: Gained carrier  /  Lost carrier
# A per-interface state file gates events, which both deduplicates the
# overlapping sources and provides the baseline for the data-volume delta.
logger_collect_network() {
    local line="$1"
    local iface=""
    # name of wifi network
    local ssid=""
    # type of event (connect or disconnect)
    local event=""
    local details=""
    # path to state-file
    local state_file=""
    local diff=""
    local rx_delta=""
    local tx_delta=""
    # regexes with literal parens/quotes are kept in variables: a bare `)` in a
    # bracket class would otherwise terminate the [[ =~ ]] expression.
    local re_nm_connect="device[[:space:]]+[(]([^)]+)[)]:[[:space:]]*Activation:[[:space:]]*[(]([^)]+)[)][[:space:]:]*connection[[:space:]]+[']([^']+)[']"
    local re_nm_state="device[[:space:]]+[(]([^)]+)[)]:[[:space:]]*state[[:space:]]+change:[[:space:]]*(activated|disconnected|deactivating|unavailable)"

    # if line is empty
    [[ -n "$line" ]] || return 1

    # NetworkManager: device (<iface>): Activation: (<type>) connection '<ssid>' ...
    if [[ "$line" =~ $re_nm_connect ]]; then
        iface="${BASH_REMATCH[1]}"
        ssid="${BASH_REMATCH[3]}"
        event="connect"
        details="event=connected network='$ssid'"

    # NetworkManager: device (<iface>): state change: activated|disconnected|...
    elif [[ "$line" =~ $re_nm_state ]]; then
        iface="${BASH_REMATCH[1]}"
        case "${BASH_REMATCH[2]}" in
            activated)
                event="connect"
                details="event=connected"
                ;;
            *)
                event="disconnect"
                details="event=disconnected state=${BASH_REMATCH[2]}"
                ;;
        esac

    # wpa_supplicant: <iface>: CTRL-EVENT-CONNECTED ...
    elif [[ "$line" =~ wpa_supplicant\[[0-9]+\]:[[:space:]]*([^:[:space:]]+):[[:space:]]*CTRL-EVENT-CONNECTED ]]; then
        iface="${BASH_REMATCH[1]}"
        event="connect"
        details="event=connected source=wpa_supplicant"
        [[ "$line" =~ (SSID|ssid)=([^[:space:]]+) ]] && details+=" ssid=${BASH_REMATCH[2]}"

    # wpa_supplicant: <iface>: CTRL-EVENT-DISCONNECTED bssid=<bssid> reason=...
    elif [[ "$line" =~ wpa_supplicant\[[0-9]+\]:[[:space:]]*([^:[:space:]]+):[[:space:]]*CTRL-EVENT-DISCONNECTED ]]; then
        iface="${BASH_REMATCH[1]}"
        event="disconnect"
        details="event=disconnected source=wpa_supplicant"
        [[ "$line" =~ bssid=([^[:space:]]+) ]] && details+=" bssid=${BASH_REMATCH[1]}"
        [[ "$line" =~ reason=([^[:space:]]+) ]] && details+=" reason=${BASH_REMATCH[1]}"

    # systemd-networkd: <iface>: Gained carrier
    elif [[ "$line" =~ ([^:[:space:]]+):[[:space:]]*Gained[[:space:]]+carrier ]]; then
        iface="${BASH_REMATCH[1]}"
        event="connect"
        details="event=connected source=systemd-networkd"

    # systemd-networkd: <iface>: Lost carrier
    elif [[ "$line" =~ ([^:[:space:]]+):[[:space:]]*Lost[[:space:]]+carrier ]]; then
        iface="${BASH_REMATCH[1]}"
        event="disconnect"
        details="event=disconnected source=systemd-networkd"

    else
        # ignore unrecognized lines
        return 1
    fi

    # checks if sth. was tracked
    [[ -n "$event" && -n "$iface" ]] || return 1

    # generating path to state file
    state_file="$(_logger_net_state_file "$iface")"


    if [[ "$event" == "connect" ]]; then
        # already tracked as connected -> deduplicate overlapping sources
        [[ -f "$state_file" ]] && return 0

        _logger_net_state_save "$iface"

        logger_event \
            "NETWORK" \
            "CONNECTION" \
            "SYSTEM" \
            "SUCCESS" \
            "LOW" \
            --source "$iface" \
            --target "${ssid:--}" \
            --device "$iface" \
            --details "$details"
        return 0
    fi

    # disconnect: enrich with the byte volume since the connection baseline
    # calculating transmitted bytes sice transmission start
    diff="$(_logger_net_state_diff "$iface")"
    # NF ... count of field of one line
    # searching through all fields, if prefix rx=, remove prefix and return value
    rx_delta="$(printf '%s' "$diff" | awk '{for (i=1;i<=NF;i++) if ($i ~ /^rx=/) {sub(/^rx=/,"",$i); print $i}}')"
    # identical to rx
    tx_delta="$(printf '%s' "$diff" | awk '{for (i=1;i<=NF;i++) if ($i ~ /^tx=/) {sub(/^tx=/,"",$i); print $i}}')"
    # adding volume to details, if existing
    [[ -n "$rx_delta" ]] && details+=" rx_bytes=$rx_delta"
    [[ -n "$tx_delta" ]] && details+=" tx_bytes=$tx_delta"

    logger_event \
        "NETWORK" \
        "DISCONNECTION" \
        "SYSTEM" \
        "SUCCESS" \
        "LOW" \
        --source "$iface" \
        --target "${ssid:--}" \
        --device "$iface" \
        --details "$details"
    return 0
}
