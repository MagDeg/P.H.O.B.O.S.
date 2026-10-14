drive_enable() {

    local service_file="/etc/systemd/system/phobos-drive-trigger.service"
    local udev_file="/etc/udev/rules.d/99-phobos-drive.rules"
    local phobos_bin
    local phobos_user

    # checking for root privileges
    if [[ "$EUID" -ne 0 ]]; then
        error "This command requires root privileges."
        hint "Run: sudo phobos drive enable"
        return 1
    fi

    # find phobos binary -> will late be startedt by stystemd
    phobos_bin=$(command -v phobos)

    # checking if binary exists
    if [[ -z "$phobos_bin" ]]; then
        error "phobos executable not found."
        return 1
    fi

    # find current user 
    phobos_user=$(logname 2>/dev/null)

    # checking if user exits
    if [[ -z "$phobos_user" ]]; then
        error "Could not determine the logged-in user."
        return 1
    fi


    # creating systemd-service
    # writing serive file
    # Type=oneshot : only runned once
    # User=$phobos_user : not runned as root
    # sleep 3 : wait for mounting process
    # phobos drive_trigger : drive backups prüfen und ausführen
    cat > "$service_file" << EOF
[Unit]
Description=PHOBOS drive backup trigger
After=udisks2.service

[Service]
Type=oneshot
User=$phobos_user
ExecStart=/bin/bash -c 'sleep 3; $phobos_bin drive_trigger'
EOF
    
    # creating udev-rules
    # if a labed device is added, systemd shall start PHOBOS-Drive-Service
    cat > "$udev_file" << EOF
ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_LABEL}!="", TAG+="systemd", ENV{SYSTEMD_WANTS}+="phobos-drive-trigger.service"
EOF

    # restarting service to update files
    systemctl daemon-reload
    # loading the nuew udev rules
    udevadm control --reload-rules

    success "PHOBOS drive trigger enabled."
}

drive_disable() {

    local service_file="/etc/systemd/system/phobos-drive-trigger.service"
    local udev_file="/etc/udev/rules.d/99-phobos-drive.rules"

    # checking for root privileges
    if [[ "$EUID" -ne 0 ]]; then
        error "This command requires root privileges."
        hint "Run: sudo phobos drive disable"
        return 1
    fi

    # removing service file and udev rules
    rm -f "$service_file"
    rm -f "$udev_file"

    # reloarding and restarting to update 
    systemctl daemon-reload
    udevadm control --reload-rules

    success "PHOBOS drive trigger disabled."
}

drive_status() {

    local service_file="/etc/systemd/system/phobos-drive-trigger.service"
    local udev_file="/etc/udev/rules.d/99-phobos-drive.rules"

    header "PHOBOS drive trigger"

    # if a service file exists, the service is active
    if [[ -f "$service_file" ]]; then
        field "Service:" "installed" "$C_GREEN"
    else
        field "Service:" "not installed" "$C_GRAY"
    fi

    # if a udev_file exits, the udev rules are installed
    if [[ -f "$udev_file" ]]; then
        field "udev rule:" "installed" "$C_GREEN"
    else
        field "udev rule:" "not installed" "$C_GRAY"
    fi

    # if both files exist, the integration is enabled
    if [[ -f "$service_file" && -f "$udev_file" ]]; then
        field "Integration:" "enabled" "$C_GREEN"
    else
        field "Integration:" "disabled" "$C_GRAY"
    fi

    echo ""
    printf '%sLast service runs:%s\n' "$C_BOLD" "$C_RESET"
    # pipeline
    # showing log-entries of this service
    # -n 5 : only the last 5
    # --no-pager : return as plain text
    # 2>/devc/null : if there is any error it will not be displayed
    # grep -q : checks quietly if phobos-drive-trigger.service exists in the oputput, if yes it will be displayed
    if journalctl -u phobos-drive-trigger.service -n 5 --no-pager 2>/dev/null | grep -q "phobos-drive-trigger.service"; then
        journalctl -u phobos-drive-trigger.service -n 5 --no-pager
    else
        hint "No service execution recorded."
    fi
}