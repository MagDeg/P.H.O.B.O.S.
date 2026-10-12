#!/bin/bash

# syscall number -> name, per architecture.
# only syscalls PHOBOS audits are listed.
# For x86 Processors
declare -A LOGGER_AUDIT_SYSCALLS_X86_64=(
    [2]=open [85]=creat [257]=openat [437]=openat2
    [76]=truncate [77]=ftruncate
    [82]=rename [264]=renameat [316]=renameat2
    [87]=unlink [263]=unlinkat
    [86]=link [265]=linkat [88]=symlink [266]=symlinkat
)
# for ARM Processors
declare -A LOGGER_AUDIT_SYSCALLS_AARCH64=(
    [56]=openat [437]=openat2
    [45]=truncate [46]=ftruncate
    [38]=renameat [276]=renameat2
    [35]=unlinkat
    [37]=linkat [36]=symlinkat
)

# prints the syscall name for number $1 on the current architecture,
# or nothing when the number is unknown.
logger_audit_syscall_name() {
    local num="$1"

    # uname -m : returns architecture of device
    case "$(uname -m)" in
        x86_64|i386|i686)
            printf '%s' "${LOGGER_AUDIT_SYSCALLS_X86_64[$num]:-}"
            ;;
        aarch64|arm64)
            printf '%s' "${LOGGER_AUDIT_SYSCALLS_AARCH64[$num]:-}"
            ;;
        *)
            printf '%s' ""
            ;;
    esac
}

# extracts the value of key $2 from an audit record line $1.
# quoted values (name="...") and bare values (pid=123) are both supported.
_logger_audit_field() {
    local line="$1"
    local key="$2"

    # REGEX searches entries like name="/home/<user>/my file.txt"
    if [[ "$line" =~ (^|[[:space:]])${key}=\"([^\"]*)\" ]]; then
        # BASH_REMATCH[2] contains actual field value
        printf '%s' "${BASH_REMATCH[2]}"
        return 0
    fi
    # REGEX for entries without "", just simple deklarations
    if [[ "$line" =~ (^|[[:space:]])${key}=([^[:space:]]+) ]]; then
        printf '%s' "${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

# prints the name of the first PATH record whose nametype is $1.
# the arrays are passed by name: $2 names, $3 nametypes.
_logger_audit_path_by_type() {
    local want="$1"
    local -n names="$2"
    local -n types="$3"
    local i
    for i in "${!names[@]}"; do
        if [[ "${types[$i]}" == "$want" ]]; then
            printf '%s' "${names[$i]}"
            return 0
        fi
    done
    return 1
}

# prints the name of the first PATH record that is not a PARENT (a directory).
_logger_audit_path_first() {
    local -n names="$1"
    local -n types="$2"
    local i
    for i in "${!names[@]}"; do
        if [[ "${types[$i]}" != "PARENT" ]]; then
            printf '%s' "${names[$i]}"
            return 0
        fi
    done
    return 1
}

# logger_collect_audit_block "<multiline audit block>"
# parses one complete audit group and emits a single FILE event.
logger_collect_audit_block() {
    local block="$1"
    local line
    local syscall_num="" success="" pid="" ppid="" auid="" uid=""
    local comm="" exe="" audit_key="" cwd=""
    # local -a creates local array with indizes
    local -a path_names=()
    local -a path_ntypes=()

    # if audit block is empty, return
    [[ -n "$block" ]] || return 1

    while IFS= read -r line; do
        # iterate over every line in block
        case "$line" in
            # if line contains type=SYSCALL
            *type=SYSCALL*)
                # extracting general informations from line
                syscall_num="$(_logger_audit_field "$line" syscall)"
                success="$(_logger_audit_field "$line" success)"
                pid="$(_logger_audit_field "$line" pid)"
                ppid="$(_logger_audit_field "$line" ppid)"
                auid="$(_logger_audit_field "$line" auid)"
                uid="$(_logger_audit_field "$line" uid)"
                comm="$(_logger_audit_field "$line" comm)"
                exe="$(_logger_audit_field "$line" exe)"
                audit_key="$(_logger_audit_field "$line" key)"
                ;;
            # if line contains type=CWD (durrent working directory)
            *type=CWD*)
                # needed to trasform absolute filepaths to relative
                cwd="$(_logger_audit_field "$line" cwd)"
                ;;
            # if line contains type=PATH
            *type=PATH*)
                # saving filepaths and pathtypes in arrays
                path_names+=("$(_logger_audit_field "$line" name)")
                path_ntypes+=("$(_logger_audit_field "$line" nametype)")
                ;;
        esac
    done <<< "$block"

    # only handle events produced by the PHOBOS rules (key=phobos-file)  # [NEW]
    [[ "$audit_key" == "phobos-file" ]] || return 1  # [NEW]

    # skip the sudo helper's own bookkeeping files (tickets, lecture file,
    # ...); commands launched under sudo keep their own comm/exe.
    if [[ "$comm" == "sudo" || "${exe##*/}" == "sudo" ]]; then
        return 1
    fi

    # resolve the syscall name; skip unknown syscalls
    local name

    # transforming number to name
    name="$(logger_audit_syscall_name "$syscall_num")"
    [[ -n "$name" ]] || return 1

    # source/target come from PATH records by nametype: PARENT records name a
    # directory, never the affected file, so they are skipped.
    local source
    local target=""
    source="$(_logger_audit_path_first path_names path_ntypes)"

    # map syscall -> schema action + severity
    local action="" severity=""
    case "$name" in
        # rename or move
        rename|renameat|renameat2)
            local old_path
            local new_path
            old_path="$(_logger_audit_path_by_type DELETE path_names path_ntypes)"
            new_path="$(_logger_audit_path_by_type CREATE path_names path_ntypes)"
            [[ -n "$old_path" ]] && source="$old_path"
            [[ -n "$new_path" ]] && target="$new_path"
            # %/* removes last / and everything after it
            # if old = new, rename
            if [[ "${source%/*}" == "${target%/*}" ]]; then
                action="RENAME"
            # if not, move
            else
                action="MOVE"
            fi
            severity="LOW"
            ;;
        # delete
        unlink|unlinkat)
            local del_path
            del_path="$(_logger_audit_path_by_type DELETE path_names path_ntypes)"
            [[ -n "$del_path" ]] && source="$del_path"
            action="DELETE"
            severity="HIGH"
            ;;
        # create links (another name for same file (hardlink) or creating new referencefile (symlink)) 
        link|linkat|symlink|symlinkat)
            local link_path
            local ref_path
            link_path="$(_logger_audit_path_by_type CREATE path_names path_ntypes)"
            ref_path="$(_logger_audit_path_by_type NORMAL path_names path_ntypes)"
            [[ -n "$link_path" ]] && source="$link_path"
            [[ -n "$ref_path" ]] && target="$ref_path"
            action="CREATE"
            severity="LOW"
            ;;
        # change of filesizes
        truncate|ftruncate)
            action="MODIFY"
            severity="MEDIUM"
            ;;
        # open file or create (only a real creation has nametype=CREATE)
        open|openat|openat2|creat)
            local create_path
            create_path="$(_logger_audit_path_by_type CREATE path_names path_ntypes)"
            [[ -n "$create_path" ]] || return 1
            source="$create_path"
            action="CREATE"
            severity="LOW"
            ;;
        *)
            return 1
            ;;
    esac

    # make relative paths absolute via the CWD when possible
    if [[ -n "$source" && "$source" != /* && -n "$cwd" ]]; then
        source="$cwd/$source"
    fi
    if [[ -n "$target" && "$target" != /* && -n "$cwd" ]]; then
        target="$cwd/$target"
    fi

    # a source path is mandatory
    [[ -n "$source" ]] || return 1

    # attribute the event to the login user (auid); fall back gracefully
    local user="$auid"
    # if auid is missing or equals one of those two special values, user is set to SYSTEM
    if [[ -z "$auid" || "$auid" == "4294967295" || "$auid" == "unset" ]]; then
        user="SYSTEM"
    # if valid auid exists
    else
        local resolved
        # getent passwd "$auid" : extracts user with UID from usermanagement
        # 2>/dev/null : suppresses error messages
        # | transfers result to cut
        # cut -d: -f1 : returns first field seperated by : (the username)
        resolved="$(getent passwd "$auid" 2>/dev/null | cut -d: -f1)"
        # only uses name if found
        [[ -n "$resolved" ]] && user="$resolved"
    fi

    # success/failed from the syscall result
    local status="SUCCESS"
    [[ "$success" == "no" ]] && status="FAILED"

    # free-form metadata kept in details
    # creating string with syscall (name of system that called), exe (ausführbares Programm), pid (process-id)
    local details="syscall=$name exe=$exe pid=$pid"
    # if "$comm" is not empty, adding processname
    [[ -n "$comm" ]] && details+=" comm=$comm"
    # if "$audit_key" exists, will be added
    [[ -n "$audit_key" ]] && details+=" key=$audit_key"

    # if target path exists
    if [[ -n "$target" ]]; then
        # creating logger event
        logger_event \
            "FILE" \
            "$action" \
            "$user" \
            "$status" \
            "$severity" \
            --source "$source" \
            --target "$target" \
            --details "$details"
    else
        # creating special event, if no target exists
        logger_event \
            "FILE" \
            "$action" \
            "$user" \
            "$status" \
            "$severity" \
            --source "$source" \
            --details "$details"
    fi
}
