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
        echo "Could not create installation directory: $install_dir"
        return 1
    fi

    # copy the main PHOBOS script into the installation directory
    if ! sudo cp "$project_dir/phobos.sh" "$install_dir/phobos.sh"; then
        echo "Could not install phobos.sh"
        return 1
    fi

    # copy all library files into the installation directory
    #
    # The "." means:
    # copy the contents of lib/
    # and not the lib directory itself.
    if ! sudo cp -r "$project_dir/lib/." "$install_dir/"; then
        echo "Could not install PHOBOS libraries"
        return 1
    fi

    # make the main PHOBOS script executable
    if ! sudo chmod +x "$install_dir/phobos.sh"; then
        echo "Could not make phobos.sh executable"
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
        echo "Could not create /usr/local/bin/phobos"
        return 1
    fi

    echo "PHOBOS successfully installed!"
}


check_dependencies() {
    # exists a runnable command called xxhsum?
    # if installed, sth. like this will be returned /usr/bin/xxhsum
    # &> /dev/null suppresses a displayed massage (sth. like a data garbage can)
    if ! command -v xxhsum &> /dev/null; then
        # in case system runns on ubuntu/debian needed tools will be installed with apt manager
        if command -v apt &> /dev/null; then
            sudo apt update
            # -y automatically approves all questions privded with yes
            sudo apt install -y xxhash

        # in case using fedora/RHEL
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y xxhash
        # in case using Arch Linux
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm xxhash
        # in case there is no supported package manager
        else
            echo "No supported package manager was found."
            # ends total script
            exit 1
        fi
    fi
}

# returns version of phobos system
version() {
    echo "$VERSION"
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
    echo "Connected drives"
    echo "----------------"

    lsblk -pnro NAME,LABEL,FSTYPE,SIZE,MOUNTPOINT,TYPE |
        awk '$6 == "part" && ($2 != "" || $5 != "") {
            printf "Device:     %s\n", $1
            printf "Label:      %s\n", ($2 != "" ? $2 : "-")
            printf "Filesystem: %s\n", ($3 != "" ? $3 : "-")
            printf "Size:       %s\n", $4
            printf "Mountpoint: %s\n", ($5 != "" ? $5 : "-")
            printf "\n"
        }'
}