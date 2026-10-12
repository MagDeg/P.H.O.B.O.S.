#!/bin/bash


# new method to print error messages to stderr, so actual commands stay clean
logger_error() {
    printf '%s\n' "$*" >&2
}

# method to check, if command is run as root
# $ 1 is command user should re-run with sudo 
logger_require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        logger_error "This command requires root privileges."
        logger_error "Run: sudo phobos ${1:-logger}"
        return 1
    fi
    return 0
}

# logger_event <category> <action> <user> <status> <severity> [options]
#
# Required positional fields map 1:1 onto the event schema (see EVENT_SPEC.md).
# Optional fields are passed as flags:
#   --source <value>   where the action originated
#   --target <value>   object/destination affected
#   --device <value>   device involved
#   --details <value>  free-form extra information
#
# Optional fields default to "-" (the schema's "no value" marker).
# Returns 0 when the event was validated and stored, non-zero otherwise.
logger_event() {
    # check if the five mandatory arguments exit
    if [[ $# -lt 5 ]]; then
        logger_error "Usage: logger_event <category> <action> <user> <status> <severity> [options]"
        return 1
    fi

    local category="$1"
    local action="$2"
    local user="$3"
    local status="$4"
    local severity="$5"

    # optional fields start out empty and are filled by the option loop.
    local source="-"
    local target="-"
    local device="-"
    local details="-"

    # drop the five mandatory arguments so only options remain.
    shift 5

    # iterating over remaining arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --source|--target|--device|--details)
                # strip the leading "--" to get the variable name ("source"...).
                local option="${1#--}"

                # checking if privided argument is empty
                #${2:-} makes argument expand to -, if there is no argument, instead of erroring
                if [[ -z "${2:-}" ]]; then
                    logger_error "Missing $option."
                    return 1
                fi

                # printf -v assigns the value to the variable named by $option.
                printf -v "$option" '%s' "$2"
                # skipping argument to continue loop
                shift 2
                ;;
            *)
                logger_error "Unknown logger option: $1"
                return 1
                ;;
        esac
    done

    # schema validation
    # validate manatory arguments
    logger_validate_required_fields "$category" "$action" "$user" "$status" "$severity" || return 1

    # validate category with possible categories like provided in EVENT_SPEC.md
    if ! logger_validate_category "$category"; then
        logger_error "Invalid logger category: $category"
        return 1
    fi

    # validate action with possible actions like provided in EVENT_SPEC.md
    if ! logger_validate_action "$category" "$action"; then
        logger_error "Invalid action '$action' for category '$category'"
        return 1
    fi

    # validate status with possible status like provided in EVENT_SPEC.md
    if ! logger_validate_status "$status"; then
        logger_error "Invalid logger status: $status"
        return 1
    fi

    # validate severity with possible severities like provided in EVENT_SPEC.md
    if ! logger_validate_severity "$severity"; then
        logger_error "Invalid logger severity: $severity"
        return 1
    fi

    local id
    local timestamp
    local event

    # generating radom number ad event id
    id="$(logger_generate_id)"
    # gettin gtimestamp as ISO 8601
    timestamp="$(date --iso-8601=seconds)"

    # one field per line
    # order is fixed by  storage format.
    event="id=$id
timestamp=$timestamp
category=$category
action=$action
user=$user
source=$source
target=$target
device=$device
status=$status
severity=$severity
details=$details"

    # try storing event
    if ! logger_store_event "$event"; then
        logger_error "Failed to store logger event."
        return 1
    fi

    return 0
}
