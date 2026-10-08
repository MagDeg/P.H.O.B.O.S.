# creating a new scheduler job -> a backup automation
schedule_add() {
    # defining paramters as local variables
    local job_name="$1" # identifier for the job
    local source="$2"
    local destination="$3"
    local interval="weekly" # parameter for backup interval
    local drive="" # optional parameter, for now empty
    local trigger="timer" # default trigger for backup

    # checking whether the required parameters were provided
    if [[ -z "$job_name" || -z "$source" || -z "$destination" ]]; then
        echo "Usage: phobos schedule add <name> <source> <destination> [--interval <interval>] [--drive <label>] [--trigger <timer|drive>]"
        return 1
    fi

    # checking optional parameters
    # skipping the mandatory parameters, so only the optional parameter is left
    shift 3

    # $# means number of remaining arguments
    # -gt means greater than
    while [[ $# -gt 0 ]]; do
        case "$1" in
            # if the first param equals --interval
            --interval) 
                # checking if interval is provided
                if [[ -z "$2" ]]; then
                    echo "Missing interval."
                    return 1
                fi

                #setting local variable
                interval="$2"
                # moving to next parameter
                shift 2
                ;;

            # if the first param equals --drive
            --drive)
                # checking if drive name is provided
                if [[ -z "$2" ]]; then
                    echo "Missing drive label."
                    return 1
                fi

                # setting local variable
                drive="$2"
                # moving to next parameters
                shift 2
                ;;
            #if param equals --trigger
            --trigger)
                # checking if trigger is provided
                if [[ -z "$2" ]]; then
                    echo "Missing trigger."
                    return 1
                fi

                #setting local variable 
                trigger="$2"
                #moving to next parameters
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # checking whether the source directory exists
    if [[ ! -d "$source" ]]; then
        echo "Source directory not found: $source"
        return 1
    fi

    # only the supported intervals are allowed
    # TODO: MAKE INTERVALS CUSTUMIZABLE AND STORED IN CONFIG.SH LIKE NO_COMPRESSION_EXTENSIONS
    case "$interval" in
        hourly|daily|weekly|monthly)
            ;;
        *)
            echo "Invalid interval."
            echo "Allowed: hourly, daily, weekly, monthly"
            return 1
            ;;
    esac

    # checking supported triggers
    case "$trigger" in
        timer|drive)
            ;;
        *)
            echo "Invalid trigger."
            echo "Allowed: timer, drive"
            return 1
            ;;
    esac

    #drive trigger requires a drive
    if [[ "$trigger" == "drive" && "$destination" = /* ]]; then
        echo "Destination must be relative when using --trigger drive."
        return 1
    fi

    # timer trigger must not use a drive
    if [[ "$trigger" == "timer" && -n "$drive" ]]; then
        echo "--drive can only be used with --trigger drive."
        return 1
    fi

    # creating the PHOBOS directories
    # -p creats all parent-directories if they are not already existing
    mkdir -p "$HOME/.phobos/jobs"
    mkdir -p "$HOME/.phobos/state"

    # building path for .conf file
    local job_file="$HOME/.phobos/jobs/$job_name.conf"

    # prevent accidentally overwriting an existing job
    # -f means, is file existing and a normale file
    if [[ -f "$job_file" ]]; then
        echo "Scheduled backup already exists: $job_name"
        return 1
    fi

    # writing the configurations in config file
    # everything that comes upto EOF shall be transfered to cat
    # > redirects output in file

    # converting source to an absolute path
    source=$(realpath "$source")

    # converting destination to an absolute path when no drive is used
    # when a drive is used, destination remains relative to the drive mount point
    if [[ -z "$drive" ]]; then
        destination=$(realpath -m "$destination")
    fi

    # writing the configuration safely
    {
        printf 'NAME=%q\n' "$job_name"
        printf 'SOURCE=%q\n' "$source"
        printf 'DESTINATION=%q\n' "$destination"
        printf 'INTERVAL=%q\n' "$interval"
        printf 'DRIVE=%q\n' "$drive"
        printf 'TRIGGER=%q\n' "$trigger"
    } > "$job_file"

    echo "Scheduled backup created: $job_name ($trigger, $interval)"

    # -n menas string is not empty
    if [[ -n "$drive" ]]; then
        echo "Drive: $drive"
    fi
}

# executes all scheduled backup jobs whose interval has expired
schedule_run() {
    # defining parameters as local variables
    local jobs_dir="$HOME/.phobos/jobs" # path to conf-files
    local state_dir="$HOME/.phobos/state" #path to state-files

    # if those directories are missing, they will be created
    mkdir -p "$jobs_dir"
    mkdir -p "$state_dir"

    local now
    # getting Unix-time (count of seconds since fixed point)
    now=$(date +%s)

    # search through all jobs
    for job in "$jobs_dir"/*.conf; do

        # if there is no .conf file skip
        [[ -e "$job" ]] || continue

        # clearing variables, to make shure they are not remaining from previous job
        unset NAME SOURCE DESTINATION INTERVAL DRIVE TRIGGER

        source "$job"

        # drive triggered jobs are handled seperately
        if [[ "$TRIGGER" == "drive" ]]; then 
            continue
        fi


        # defining path to state file
        local state_file="$state_dir/$NAME.state"

        local last_success=0

        # checking for state in state file, if it exists loading
        if [[ -f "$state_file" ]]; then
            unset LAST_SUCCESS
            source "$state_file"
            # if varibale is empty or unset use value (0), if not use variable
            # getting time of last successfull backup
            last_success="${LAST_SUCCESS:-0}"
        fi

        local interval_seconds

        # setting intervall according to configuration
        case "$INTERVAL" in
            hourly) interval_seconds=3600 ;;
            daily) interval_seconds=86400 ;;
            weekly) interval_seconds=604800 ;;
            monthly) interval_seconds=2592000 ;;
            *)
                echo "Invalid interval for job: $NAME"
                continue
                ;;
        esac

        # checking if intervall is reached, meaning a backup need to be done
        if (( now - last_success >= interval_seconds )); then

            echo "Scheduled backup due: $NAME"

            # doing backup, if successfull, update last_success in state_file
            if save_folder "$SOURCE" "$DESTINATION"; then

                printf "LAST_SUCCESS=%s\n" "$now" > "$state_file"

            fi

        fi

    done
}

# enables the automatic PHOBOS scheduler
# connection between phobos and systemd
schedule_enable() {

    # path to userspecific systemd-files
    local systemd_dir="$HOME/.config/systemd/user"

    # create directory, if not already existing
    mkdir -p "$systemd_dir"

    # create phobos service
    #
    # UNIT:
    #       Descriptipon : just readable description
    # SERVICE
    #       oneshot : start sth. and let it run until it is finished, afterwards terminate process
    #       ExecStart : whats shall be startet (command -v phobos finds path to installed programm)
    # EOF : End of Service-File
    cat > "$systemd_dir/phobos-scheduler.service" << EOF
[Unit]
Description=PHOBOS Backup Scheduler

[Service]
Type=oneshot
ExecStart=$(command -v phobos) schedule run
EOF

    # create timer-file
    #
    # UNIT : Description of timer
    # TIMER:
    #       OnBootSec=1min : after boot timer shall run the first time 
    #       OnUnitActiveSec=1min : will be reactivated after every minute
    #       Persistent=true : missed timer-events (due to shutdown of device) can be done afterwards
    # Install ... : timer bound to systemd-timer-structure

    cat > "$systemd_dir/phobos-scheduler.timer" << EOF
[Unit]
Description=Run PHOBOS Scheduler every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # reloading configurations
    # --user : only using sytemmanger of current user not globally
    systemctl --user daemon-reload
    # timer is permanently enabled and will be restartet after restart
    systemctl --user enable --now phobos-scheduler.timer

    echo "PHOBOS scheduler enabled."
}

# disables the automatic PHOBOS scheduler
schedule_disable() {

    # diables timer-events immediatly
    systemctl --user disable --now phobos-scheduler.timer

    # remove service file
    # -f : no error if file does not exist 
    rm -f "$HOME/.config/systemd/user/phobos-scheduler.service"
    # remove timer file
    rm -f "$HOME/.config/systemd/user/phobos-scheduler.timer"

    # reloading configurations
    systemctl --user daemon-reload

    echo "PHOBOS scheduler disabled."
}

# displays the scheduler status
schedule_status() {
    # showing status of timer
    # --no-pager value is send directly to terminal
    systemctl --user status phobos-scheduler.timer --no-pager
}

# removes a scheduled backup job by name
schedule_remove() {
    # defining parameters as local variables
    local job_name="$1"

    # checking whether a job name was provided
    if [[ -z "$job_name" ]]; then
        echo "Usage: phobos schedule remove <name>"
        return 1
    fi

    # defining path to necessary files
    local job_file="$HOME/.phobos/jobs/$job_name.conf"
    local state_file="$HOME/.phobos/state/$job_name.state"

    # checking whether the scheduled job exists
    if [[ ! -f "$job_file" ]]; then
        echo "Scheduled backup not found: $job_name"
        return 1
    fi

    # removing the job configuration
    rm -f "$job_file"

    # removing the state information
    rm -f "$state_file"

    echo "Scheduled backup removed: $job_name"
}

# displays all scheduled backup jobs
schedule_list() {

    # defining path to jobs
    local jobs_dir="$HOME/.phobos/jobs"

    # checking whether the jobs directory exists
    if [[ ! -d "$jobs_dir" ]]; then
        echo "No scheduled backups found."
        return 0
    fi

    # varibale to check if there was at least one conf file found
    local found=0

    echo "Scheduled backups"
    echo "-----------------"

    for job in "$jobs_dir"/*.conf; do

        # skip if no configuration files exist
        [[ -e "$job" ]] || continue

        found=1

        # load job configuration
        unset NAME SOURCE DESTINATION INTERVAL DRIVE
        source "$job"

        echo "Name:        $NAME"
        echo "Source:      $SOURCE"
        echo "Destination: $DESTINATION"
        echo "Interval:    $INTERVAL"
        echo "Trigger:     $TRIGGER"

        if [[ -n "$DRIVE" ]]; then
            echo "Drive:       $DRIVE"
        else
            echo "Drive:       none"
        fi

        echo ""

    done

    if (( found == 0 )); then
        echo "No scheduled backups found."
    fi
}

find_drive() {
    local drive_label="$1" # defining parameters as local variables

    # checking if a label was gives as param
    if [[ -z "$drive_label" ]]; then
        return 1
    fi

    local mountpoint

    # findmnt gets informations about mounted filesystems
    # -rn raw output without table format & without headlines
    # -s search source with this LABEL
    # -o TARGET only return mountpoint
    mountpoint=$(findmnt -rn -S "LABEL=$drive_label" -o TARGET)

    # checking if drive was found
    if [[ -z "$mountpoint" ]]; then
        return 1
    fi

    printf '%s\n' "$mountpoint"
}

drive_trigger() {

    local jobs_dir="$HOME/.phobos/jobs" # path to job-configurations
    local state_dir="$HOME/.phobos/state" 

    # create directories, if they are not already existing
    mkdir -p "$jobs_dir"
    mkdir -p "$state_dir"

    # search through all jobs
    for job in "$jobs_dir"/*.conf; do
        # if jopb-file does not exist, jump to next job-file
        [[ -e "$job" ]] || continue

        # clear old variables
        unset NAME SOURCE DESTINATION INTERVAL DRIVE TRIGGER

        # load job configurations
        source "$job"

        # only drive triggered jobs are handled here
        if [[ "$TRIGGER" != "drive" ]]; then
            continue
        fi

        # checking if a drive was given as param
        if [[ -z "$DRIVE" ]]; then
            echo "Drive trigger without drive configured: $NAME"
            continue
        fi

        local mountpoint

        # getting mountpoint for drive label
        mountpoint=$(find_drive "$DRIVE")

        # if there is no mountpoint, the drive is not available or notr plugged in 
        if [[ -z "$mountpoint" ]]; then
            continue
        fi

        # creating target path
        local target="$mountpoint/$DESTINATION"

        echo "Drive detected: $DRIVE"
        echo "Scheduled backup: $NAME"
        echo "Destination: $target"

        # start backup
        if save_folder "$SOURCE" "$target"; then
            local state_file="$state_dir/$NAME.state"
            printf "LAST_SUCCESS=%s\n" "$(date +%s)" > "$state_file"
        else
            echo "Backup failed: $NAME"
        fi

    done
}