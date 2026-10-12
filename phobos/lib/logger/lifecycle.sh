#!/bin/bash

# installs udev rule and prepares storage
# requires root
logger_enable() {
    logger_require_root "logger enable" || return 1

    # creating needed dirs and files
    logger_storage_init || return 1

    # verify LOGGER_UDEV_HELPER exists
    if [[ ! -f "$LOGGER_UDEV_HELPER" ]]; then
        logger_error "Logger udev helper not found:"
        logger_error "$LOGGER_UDEV_HELPER"
        return 1
    fi


    # user can read, write, execute, all others can only read, write
    chmod 755 "$LOGGER_UDEV_HELPER"

    # writing udes-rules to file
    cat > "$LOGGER_UDEV_RULES" << EOF
ACTION=="add", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", RUN+="$LOGGER_UDEV_HELPER"
ACTION=="remove", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", RUN+="$LOGGER_UDEV_HELPER"
EOF

    # user can read, write, all others only read
    chmod 644 "$LOGGER_UDEV_RULES"

    # reload udev-rules
    udevadm control --reload-rules

    # verify journal helper exists
    if [[ ! -f "$LOGGER_JOURNAL_HELPER" ]]; then
        logger_error "Logger journal helper not found:"
        logger_error "$LOGGER_JOURNAL_HELPER"
        return 1
    fi

    # helper must be executable
    chmod 755 "$LOGGER_JOURNAL_HELPER"

    # journal collector service
    # feeds journal lines (sudo, logins, ...) into the logger
    cat > "$LOGGER_JOURNAL_UNIT" << EOF
[Unit]
Description=PHOBOS logger journal collector
After=systemd-journald.service
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=/bin/bash -c 'journalctl -f -o short -n 0 | $LOGGER_JOURNAL_HELPER'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$LOGGER_JOURNAL_UNIT"

    # activate the service
    if command -v systemctl &> /dev/null; then
        systemctl daemon-reload
        systemctl enable --now phobos-logger-journal.service
    else
        logger_error "systemctl not found; journal collector service not started."
    fi

    echo "PHOBOS logger enabled."
}

# rmeoves udev-rules
# requires root
logger_disable() {
    logger_require_root "logger disable" || return 1

    # if rule-file exists, remove is
    [[ -f "$LOGGER_UDEV_RULES" ]] && rm -f "$LOGGER_UDEV_RULES"

    # reload udev-rules
    udevadm control --reload-rules

    # stop and remove the journal collector service
    if command -v systemctl &> /dev/null; then
        systemctl disable --now phobos-logger-journal.service 2>/dev/null
    fi
    rm -f "$LOGGER_JOURNAL_UNIT"
    if command -v systemctl &> /dev/null; then
        systemctl daemon-reload
    fi

    echo "PHOBOS logger disabled."
    echo "Existing log data was preserved."
}

# prints current logger state
# requires root.
logger_status() {
    logger_require_root "logger status" || return 1

    echo "PHOBOS Logger"
    echo "-------------"

    if [[ -f "$LOGGER_UDEV_RULES" ]]; then
        echo "Drive monitoring: enabled"
    else
        echo "Drive monitoring: disabled"
    fi

    if [[ -f "$LOGGER_JOURNAL_UNIT" ]] && command -v systemctl &> /dev/null && systemctl is-active --quiet phobos-logger-journal.service; then
        echo "Journal monitor:   active"
    elif [[ -f "$LOGGER_JOURNAL_UNIT" ]]; then
        echo "Journal monitor:   installed (inactive)"
    else
        echo "Journal monitor:   disabled"
    fi

    if [[ -d "$LOGGER_DIR" ]]; then
        echo "Storage:           available"
    else
        echo "Storage:           not initialized"
    fi

    if [[ -f "$EVENT_LOG" ]]; then
        echo "Events:            $(grep -c '^id=' "$EVENT_LOG" 2>/dev/null)"
    else
        echo "Events:            0"
    fi

    if [[ -f "$LOGGER_CHAIN_FILE" ]]; then
        echo "Integrity chain:   available"
    else
        echo "Integrity chain:   not initialized"
    fi

    echo ""
}
