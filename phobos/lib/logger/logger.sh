logger_event() {

    if [[ $# -lt 5 ]]; then
        echo "Usage: logger_event <category> <action> <user> <status> <severity> [options]"
        return 1
    fi

    local category="$1"
    local action="$2"
    local user="$3"
    local status="$4"
    local severity="$5"

    local source="-"
    local target="-"
    local device="-"
    local details="-"

    shift 5

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --source)
                if [[ -z "$2" ]]; then
                    echo "Missing source."
                    return 1
                fi

                source="$2"
                shift 2
                ;;

            --target)
                if [[ -z "$2" ]]; then
                    echo "Missing target."
                    return 1
                fi

                target="$2"
                shift 2
                ;;

            --device)
                if [[ -z "$2" ]]; then
                    echo "Missing device."
                    return 1
                fi

                device="$2"
                shift 2
                ;;

            --details)
                if [[ -z "$2" ]]; then
                    echo "Missing details."
                    return 1
                fi

                details="$2"
                shift 2
                ;;

            *)
                echo "Unknown logger option: $1"
                return 1
                ;;
        esac
    done

    if ! logger_validate_required_fields \
        "$category" \
        "$action" \
        "$user" \
        "$status" \
        "$severity"; then
        return 1
    fi

    if ! logger_validate_category "$category"; then
        echo "Invalid logger category: $category"
        return 1
    fi

    if ! logger_validate_action "$category" "$action"; then
        echo "Invalid action '$action' for category '$category'"
        return 1
    fi

    if ! logger_validate_status "$status"; then
        echo "Invalid logger status: $status"
        return 1
    fi

    if ! logger_validate_severity "$severity"; then
        echo "Invalid logger severity: $severity"
        return 1
    fi

    local id
    local timestamp
    local event

    id="$(logger_generate_id)"
    timestamp="$(date --iso-8601=seconds)"

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

    if ! logger_store_event "$event"; then
        echo "Failed to store logger event."
        return 1
    fi

    return 0
}