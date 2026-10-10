logger_enable() {
    local logger_dir="/var/lib/phobos/logger"
    local udev_file="/etc/udev/rules.d/98-phobos-logger.rules"
    local helper_file="/usr/local/lib/phobos/logger/logger_udev.sh"

    if [[ "$EUID" -ne 0 ]]; then
        echo "This command requires root privileges."
        echo "Run: sudo phobos logger enable"
        return 1
    fi

    mkdir -p "$logger_dir"
    chmod 700 "$logger_dir"

    touch "$logger_dir/events.log"
    chmod 600 "$logger_dir/events.log"

    touch "$logger_dir/chain.hash"
    chmod 600 "$logger_dir/chain.hash"

    if [[ ! -f "$helper_file" ]]; then
        echo "Logger udev helper not found:"
        echo "$helper_file"
        return 1
    fi

    chmod 755 "$helper_file"

    cat > "$udev_file" << EOF
ACTION=="add", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", RUN+="$helper_file"
ACTION=="remove", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", RUN+="$helper_file"
EOF

    chmod 644 "$udev_file"

    udevadm control --reload-rules

    echo "PHOBOS logger enabled."
}

logger_disable() {
    local udev_file="/etc/udev/rules.d/98-phobos-logger.rules"

    if [[ "$EUID" -ne 0 ]]; then
        echo "This command requires root privileges."
        echo "Run: sudo phobos logger disable"
        return 1
    fi

    if [[ -f "$udev_file" ]]; then
        rm -f "$udev_file"
    fi

    udevadm control --reload-rules

    echo "PHOBOS logger disabled."
    echo "Existing log data was preserved."
}

logger_status() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "This command requires root privileges."
        echo "Run: sudo phobos logger status"
        return 1
    fi

    local logger_dir="/var/lib/phobos/logger"
    local event_log="$logger_dir/events.log"
    local chain_file="$logger_dir/chain.hash"
    local udev_file="/etc/udev/rules.d/98-phobos-logger.rules"

    echo "PHOBOS Logger"
    echo "-------------"

    if [[ -f "$udev_file" ]]; then
        echo "Drive monitoring: enabled"
    else
        echo "Drive monitoring: disabled"
    fi

    if [[ -d "$logger_dir" ]]; then
        echo "Storage:           available"
    else
        echo "Storage:           not initialized"
    fi

    if [[ -f "$event_log" ]]; then
        local event_count

        event_count=$(grep -c '^id=' "$event_log" 2>/dev/null)

        echo "Events:            $event_count"
    else
        echo "Events:            0"
    fi

    if [[ -f "$chain_file" ]]; then
        echo "Integrity chain:   available"
    else
        echo "Integrity chain:   not initialized"
    fi

    echo ""
}

logger_show() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "This command requires root privileges."
        echo "Run: sudo phobos logger show"
        return 1
    fi

    local event_log="/var/lib/phobos/logger/events.log"

    if [[ ! -f "$event_log" ]]; then
        echo "Event log not found."
        return 1
    fi

    echo "PHOBOS Logger Events"
    echo "===================="
    echo ""

    local id=""
    local timestamp=""
    local category=""
    local action=""
    local user=""
    local source=""
    local target=""
    local device=""
    local status=""
    local severity=""
    local details=""
    local event_count=0

    while IFS= read -r line; do
        if [[ "$line" == "id="* ]]; then
            id="${line#id=}"
        elif [[ "$line" == "timestamp="* ]]; then
            timestamp="${line#timestamp=}"
        elif [[ "$line" == "category="* ]]; then
            category="${line#category=}"
        elif [[ "$line" == "action="* ]]; then
            action="${line#action=}"
        elif [[ "$line" == "user="* ]]; then
            user="${line#user=}"
        elif [[ "$line" == "source="* ]]; then
            source="${line#source=}"
        elif [[ "$line" == "target="* ]]; then
            target="${line#target=}"
        elif [[ "$line" == "device="* ]]; then
            device="${line#device=}"
        elif [[ "$line" == "status="* ]]; then
            status="${line#status=}"
        elif [[ "$line" == "severity="* ]]; then
            severity="${line#severity=}"
        elif [[ "$line" == "details="* ]]; then
            details="${line#details=}"
        elif [[ "$line" == "---" ]]; then

            ((event_count++))

            echo "Event #$event_count"
            echo "----------------------------------------"
            printf "ID:        %s\n" "$id"
            printf "Timestamp: %s\n" "$timestamp"
            printf "Category:  %s\n" "$category"
            printf "Action:    %s\n" "$action"
            printf "User:      %s\n" "$user"
            printf "Source:    %s\n" "$source"
            printf "Target:    %s\n" "$target"
            printf "Device:    %s\n" "$device"
            printf "Status:    %s\n" "$status"
            printf "Severity:  %s\n" "$severity"
            printf "Details:   %s\n" "$details"
            echo ""

            id=""
            timestamp=""
            category=""
            action=""
            user=""
            source=""
            target=""
            device=""
            status=""
            severity=""
            details=""
        fi
    done < "$event_log"

    echo "Total events: $event_count"
}