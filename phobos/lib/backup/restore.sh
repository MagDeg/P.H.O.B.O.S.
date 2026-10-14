restore_file() {
    # defining parameters as local variables
    local container="$1" # path to .phbs file
    local restore_dir="$2" # path in which file shall be restored

    # checking if .phbs-container exists
    if [[ ! -f "$container" ]]; then
        error "Container not found: $container"
        return 1
    fi

    local header_size
    # reading header size (first 8 Bytes contain size of header)
    header_size=$(head -c 8 "$container")

    # validate header size
    # if header size only contains numbers (REGEX)
    # ^ beginning of text
    # [0-9] numbers from 0 to 9
    # + one or multple of those
    # $ end of text
    if ! [[ "$header_size" =~ ^[0-9]+$ ]]; then
        error "Invalid PHBS-Container."
        return 1
    fi

    # convert to decimal number
    # in bash numbers with leading 0 will normally be convertet to octal-numbers
    # 10# demands the decimal interpretation
    header_size=$((10#$header_size))

    local header
    # reading header from container
    # skip=9 : skipping first 9 bytes because they only contain header_size an newline
    # dd : reads data from file and returns only an specified area 
    # bs=1 : block size is 1 Byte
    # count="$header_size" : reads exactly amount of bytes as the size of header
    # 2>/dev/null : redirect error messages to /dev/null, so they will not be promtet to the terminal (2 stands for stderr)
    header=$(dd if="$container" bs=1 skip=9 count="$header_size" 2>/dev/null)

    # checking if header starts with PHBS to make shure it is a phobos-container
    # grep -q : search but do not return result
    if ! grep -q '^PHBS$' <<< "$header"; then
        error "Invalid PHBS-Container."
        return 1
    fi

    # variable for header values
    local filename
    local expected_hash
    local compression

    # reading values from header and plotting them into the variables by using a pipeline
    # cut -d= -f2- : -d= states that = will be used as separating character; -f2- takes filed 2 upto end
    filename=$(printf '%s\n' "$header" | grep '^FILENAME=' | cut -d= -f2-)
    expected_hash=$(printf '%s\n' "$header" | grep '^HASH=' | cut -d= -f2-)
    compression=$(printf '%s\n' "$header" | grep '^COMPRESSION=' | cut -d= -f2-)

    # cecking if filename exits, if not, file can not be restored
    if [[ -z "$filename" ]]; then
        error "Header contains no filename."
        return 1
    fi




    # if target directory does not already exists it will be created
    # -p creates also the parent-directories
    mkdir -p "$restore_dir"

    local compressed
    # creating temporary file for compression
    compressed=$(mktemp)

    # extracting payload from container and writing it to temporary file
    tail -c +$((10 + header_size)) "$container" > "$compressed"

    # creating target path
    local output="$restore_dir/$filename"

    info "Restoring: $output"

    # checking compression type
    case "$compression" in 
        # if type is gzip, file has been compressed using gzip and can be properly decompressed
        gzip) 
            # restoring file
            # gzip -d : decrompressing
            # -c : write result to stdcout, instead of overriting source file
            # > : moves output to correct file
            if ! gzip -dc "$compressed" > "$output"; then
                error "Error while decompression"
                rm -f "$compressed" "$output"
                return 1
            fi
            ;;
        # if type is none, file has not been compressed, because it was a non-compress file
        # so it will only be copied
        none)
            cp "$compressed" "$output"
            ;;
        *)
            error "Not supported compression type: $compression"
            rm -f "$compressed"
            return 1
            ;;
    esac



    # remove temporary file
    rm -f "$compressed"


    local actual_hash
    # generate hash of the restored file
    actual_hash=$(xxhsum "$output" | awk '{print $1}')

    # if those hashes dont match, sth went wrong during process (e.g. file was damaged)
    if [[ "$actual_hash" != "$expected_hash" ]]; then
        error "Hashes are not consistent!"
        hint "Expected: $expected_hash"
        hint "Received: $actual_hash"
        # remove faulty file
        rm -f "$output"
        return 1
    fi

    success "Successfully recovered: $output"
}


restore_dir() {
    # defining parameters as local variable
    local backup_dir="$1" # backup-directory
    local restore_dir="$2" # target-directory for restoring

    # if either of those parameters is empty, the funtion is not called properly
    if [[ -z "$backup_dir" || -z "$restore_dir" ]]; then
        error "Missing arguments."
        printf '\n%sUsage:%s\n' "$C_BOLD" "$C_RESET"
        printf '  %sphobos restore <backup> <target>%s\n' "$C_CYAN" "$C_RESET"
        return 1
    fi

    # checking if backup-directory exists properly
    if [[ ! -d "$backup_dir" ]]; then
        error "Backup-directory not found: $backup_dir"
        return 1
    fi

    # removing possible / from the end of paths
    backup_dir="${backup_dir%/}"
    restore_dir="${restore_dir%/}"

    # creating target-directory
    mkdir -p "$restore_dir"

    # find : searches through directory recursively
    # -type f : only uses normal files /no directories
    # -name '*.phbs' : only files that end with .phbs will be used
    # print0 : files will be separated by NULL-Byte (because filenames can in theory contain \n)
    find "$backup_dir" -type f -name '*.phbs' -print0 |
    # -r : \ will not be special interpeted
    # -d '' : using NULL-Byte as separting character
    while IFS= read -r -d '' container; do

        local relative_path
        relative_path="${container#"$backup_dir"/}"
        # removeing .phbs ending
        relative_path="${relative_path%.phbs}"

        local target_dir
        target_dir="$restore_dir/$(dirname "$relative_path")"

        # creating target directory
        mkdir -p "$target_dir"

        info "Restore: $container"

        # restore file is delageted to designated function
        if ! restore_file "$container" "$target_dir"; then
            error "Error with: $container"
        fi

    done
}