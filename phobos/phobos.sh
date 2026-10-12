#!/bin/bash
#declares interpreter for this script

# determining the real path of the currently executed PHOBOS script
#
# readlink -f resolves symbolic links.
#
# This is important because /usr/local/bin/phobos is a symbolic link
# to the actual PHOBOS script in /usr/local/lib/phobos/.
local_script="$(readlink -f "${BASH_SOURCE[0]}")"

# extracting the directory in which the actual phobos.sh is located
SCRIPT_DIR="$(dirname "$local_script")"

# checking if a separate lib directory exists
#
# In the development environment the structure is:
#
# phobos/
# ├── phobos.sh
# └── lib/
#     ├── config.sh
#     ├── utils.sh
#     └── ...
#
# During installation the library files are currently copied directly
# next to phobos.sh:
#
# /usr/local/lib/phobos/
# ├── phobos.sh
# ├── config.sh
# ├── utils.sh
# └── ...
if [[ -d "$SCRIPT_DIR/lib" ]]; then
    LIB_DIR="$SCRIPT_DIR/lib"
else
    LIB_DIR="$SCRIPT_DIR"
fi

# loading all PHOBOS libraries
source "$LIB_DIR/config.sh"
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/backup.sh"
source "$LIB_DIR/restore.sh"
source "$LIB_DIR/container.sh"
source "$LIB_DIR/scheduler.sh"
source "$LIB_DIR/integration.sh"

source "$LIB_DIR/logger/storage.sh"
source "$LIB_DIR/logger/logger.sh"
source "$LIB_DIR/logger/validation.sh"
source "$LIB_DIR/logger/collector.sh"
source "$LIB_DIR/logger/lifecycle.sh"
source "$LIB_DIR/logger/display.sh"


# case statement to handle phobos-commands
case "$1" in 
    --version)
        version
        ;;
    save_file)
        save_file "$2" "$3"
        ;; 
    check_dependencies)
        check_dependencies
        ;;
    save)
        if [[ -d "$2" ]]; then
            save_folder "$2" "$3"
        elif [[ -f "$2" ]]; then
            save_file "$2" "$3"
        else 
            echo "Source not found: $2"
            exit 1
        fi
        ;;
    info)
        info "$2"
        ;;
    add_to_path)
        add_to_path
        ;;
    restore)
        # checks if input parameter is a directory
        if [[ -d "$2" ]]; then 
            restore_dir "$2" "$3"
        elif [[ -f "$2" ]]; then 
            restore_file "$2" "$3"
        else 
            echo "Backup not found: $2"
            exit 1
        fi
        ;;
    logger)
        case "$2" in
            enable)
                logger_enable
                ;;

            disable)
                logger_disable
                ;;
            status)
                logger_status
                ;;
            verify)
                logger_verify_chain
                ;;
            show)
                logger_show
                ;;

            ingest)
                logger_collect_journal_line "$3"
                ;;

            ingest-audit)  
                logger_collect_audit_block "$3"  
                ;;

            test)
                logger_event \
                    "SYSTEM" \
                    "CONFIG_CHANGED" \
                    "$USER" \
                    "SUCCESS" \
                    "INFO" \
                    --details "manual_test"

                echo "Logger test event created."
                ;;

            *)
                echo "Usage: phobos logger {enable|disable|status|verify|show|ingest|ingest-audit|test}"
                ;;
        esac
        ;;
    drive)
        case "$2" in
            enable)
                drive_enable
                ;;
            disable)
                drive_disable
                ;;
            status)
                drive_status
                ;;
            *)
                echo "Usage: phobos drive {enable|disable|status}"
                ;;
        esac
        ;;
    drives)
        list_drives
        ;;
    drive_trigger)
        drive_trigger
        ;;
    collect-drive)
        logger_collect_drive "$2" "$3" "$4" "$5"
        ;;
    schedule)
        case "$2" in    
            add)
                # shifts argument positions (basically skips first two, because they are not needed as params here)
                shift 2
                # $@ means, all arguments will be handed through one by one
                schedule_add "$@"
                ;;
            run)
                schedule_run
                ;;
            enable)
                schedule_enable
                ;;
            disable)
                schedule_disable
                ;;
            status)
                schedule_status
                ;;
            remove)
                schedule_remove "$3"
                ;; 
            list)
                schedule_list
                ;;
            *)
                echo "Usage:"
                echo "  phobos schedule add <name> <source> <destination> <interval> [--drive <label>]"
                echo "  phobos schedule run"
                echo "  phobos schedule enable"
                echo "  phobos schedule disable"
                echo "  phobos schedule status"
                echo "  phobos schedule remove <name>"
                echo "  phobos schedule list"
                ;;
        esac
        ;;
    *)
        echo "Ungültiger Befehl"
        ;;
esac