# helper function, that returns, if a file type shall be compressed or not
# returns 0 if shall be compressed and 1 otherwise
should_compress() {
    local file="$1"


    # extracting file ending
    local ext="${file##*.}"

    # force letter so be lowercase
    ext="${ext,,}"
    
    # @ return all elements of array one by one
    for no_ext in "${NO_COMPRESS_EXTENSIONS[@]}"; do
        if [[ "$ext" == "$no_ext" ]]; then
            return 1
        fi
    done
    return 0
}

#install script as global command (adds phobos to path) -> primary for debug purposes
add_to_path() {
    # defining the directory of the current project
    #
    # BASH_SOURCE[0] contains the path of the file in which this
    # function is currently defined.
    #
    # Because this function is located in:
    #
    # phobos/lib/utils.sh
    #
    # dirname gives us:
    #
    # phobos/lib
    #
    # /.. moves one directory upwards:
    #
    # phobos
    local project_dir
    project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    # defining the installation directory for PHOBOS
    #
    # All PHOBOS library files will be stored here.
    local install_dir="/usr/local/lib/phobos"

    # create the installation directory
    #
    # -p also creates missing parent directories
    sudo mkdir -p "$install_dir"

    # check if creating the installation directory was successful
    if [[ $? -ne 0 ]]; then
        error "Could not create installation directory: $install_dir"
        return 1
    fi

    # copy the main PHOBOS script into the installation directory
    if ! sudo cp "$project_dir/phobos.sh" "$install_dir/phobos.sh"; then
        error "Could not install phobos.sh"
        return 1
    fi

    # copy all library files into the installation directory
    #
    # The "." means:
    # copy the contents of lib/
    # and not the lib directory itself.
    if ! sudo cp -r "$project_dir/lib/." "$install_dir/"; then
        error "Could not install PHOBOS libraries"
        return 1
    fi

    # make the main PHOBOS script executable
    if ! sudo chmod +x "$install_dir/phobos.sh"; then
        error "Could not make phobos.sh executable"
        return 1
    fi

    # create a symbolic link in /usr/local/bin
    #
    # This allows the command:
    #
    # phobos
    #
    # instead of:
    #
    # /usr/local/lib/phobos/phobos.sh
    if ! sudo ln -sf "$install_dir/phobos.sh" /usr/local/bin/phobos; then
        error "Could not create /usr/local/bin/phobos"
        return 1
    fi

    success "PHOBOS successfully installed!"
    hint "Run 'phobos --version' to verify the installation."
}


# installs every package PHOBOS needs to run.
# detects the package manager (apt/dnf/pacman) and installs the matching
# package names, including auditd for file-operation logging.
# returns 0 on success, 1 when no supported package manager was found.
install_dependencies() {
    local pm=""
    local core_pkgs=""
    local audit_pkgs=""

    # standard tools: xxhsum for hashing, openssl for logger event ids,
    # gzip for backup compression, coreutils/util-linux for the rest
    core_pkgs="xxhash openssl gzip coreutils util-linux"

    # package manager detection
    if command -v apt-get &> /dev/null; then
        pm="apt-get"
        audit_pkgs="auditd"
    elif command -v dnf &> /dev/null; then
        pm="dnf"
        audit_pkgs="audit"
    elif command -v pacman &> /dev/null; then
        pm="pacman"
        audit_pkgs="audit"
    else
        error "No supported package manager was found (apt/dnf/pacman)."
        return 1
    fi

    case "$pm" in
        apt-get)
            sudo apt-get update
            sudo apt-get install -y $core_pkgs $audit_pkgs
            ;;
        dnf)
            sudo dnf install -y $core_pkgs $audit_pkgs
            ;;
        pacman)
            sudo pacman -Sy --noconfirm $core_pkgs $audit_pkgs
            ;;
    esac

    success "Dependencies installed via $pm."
    return 0
}

# installs all dependencies; kept as a short alias so the
# `phobos check_dependencies` command keeps working.
check_dependencies() {
    install_dependencies
}

# returns version of phobos system
version() {
    printf '%sPHOBOS%s %s\n' "$C_BOLD" "$C_RESET" "$C_CYAN$VERSION$C_RESET"
}

log_backup() {
    # defining parameters as local variables
    # values will be handed over by save_folder()
    local source="$1"
    local backup="$2"
    local total="$3"
    local changed="$4"
    local skipped="$5"
    local errors="$6"
    local duration="$7"

    # create .phobos directory in user's home dir
    # -p means that mkdir does not report an error if dir already exists
    # log file will stored at: ~/.phobos/phobos.log
    mkdir -p "$HOME/.phobos"

    # write one complete backup entry into logfile
    # date: creates current timestamp
    # >>: appends new line to logfile instead of overriting existing logfile
    # format:
    # DATE | BACKUP | source=... | destination=... |
    # files=... | changed=... | skipped=... |
    # errors=... | duration=...s
    printf '%s | BACKUP | source=%s | destination=%s | files=%s | changed=%s | skipped=%s | errors=%s | duration=%ss\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$source" \
        "$backup" \
        "$total" \
        "$changed" \
        "$skipped" \
        "$errors" \
        "$duration" \
        >> "$HOME/.phobos/phobos.log"
}

list_drives() {
    header "Connected drives"

    # -p : print full device paths
    # -n : no header
    # -r : raw (no tree chars)+
    # -o ... : select columns
    # awk filter keeps only rows where field 6 = 'part' and either field 2 or field 5is non-empty
    lsblk -pnro NAME,LABEL,FSTYPE,SIZE,MOUNTPOINT,TYPE |
        awk -v BOLD="$C_BOLD" -v RESET="$C_RESET" -v CYAN="$C_CYAN" -v GRAY="$C_GRAY" \
        '$6 == "part" && ($2 != "" || $5 != "") {
            printf "  " GRAY "Device:"     RESET "     %s\n", BOLD CYAN $1 RESET
            printf "  " GRAY "Label:"      RESET "      %s\n", ($2 != "" ? $2 : "-")
            printf "  " GRAY "Filesystem:" RESET " %s\n", ($3 != "" ? $3 : "-")
            printf "  " GRAY "Size:"       RESET "       %s\n", BOLD $4 RESET
            printf "  " GRAY "Mountpoint:" RESET " %s\n", ($5 != "" ? $5 : "-")
            printf "\n"
        }'
}