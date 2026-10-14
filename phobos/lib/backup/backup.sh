# searches through a directory recursively and create for every found file a .phbs-Container
save_folder() {
    # defining parameters as local variables
    local source_dir="$1"
    local backup_dir="$2"

    # -z means, if the string is empty
    # if so, the parameters are not given correctly
    if [[ -z "$source_dir" || -z "$backup_dir" ]]; then
        error "Missing arguments."
        printf '\n%sUsage:%s\n' "$C_BOLD" "$C_RESET"
        printf '  %sphobos save <source> <backup>%s\n' "$C_CYAN" "$C_RESET"
        # ends function
        return 1
    fi

    # -d means, if path exists and if it is a directory
    # checks if path source directory exists
    if [[ ! -d "$source_dir" ]]; then
        error "Source directory not found: $source_dir"
        return 1
    fi


    # counts all files found by find
    local total=0

    # counts files for which new or updated .phbs-container was created
    local changed=0

    #counts files where source hash was identical to hash stored inside existing .phbs-container
    local skipped=0

    #counts files where save_file() returned error
    local errors=0

    # start time of total backup operation
    local start_time
    start_time=$(date +%s%3N)



    # removing "/" at the end of path
    # %/ means, remove / if existing from the end 
    source_dir="${source_dir%/}"


    # result of find will be given to the while - loop
    # IFS = Internal Field Separator (prohibits separation by space-characters)
    # read -r: reads input, -r prohibits special interpretation of "\"
    # -d '', read only up to the next NUL-character
    while IFS= read -r -d '' file; do
        local relative_path
        # calculate relative path (basically removes head-directory)
        relative_path="${file#"$source_dir"/}"

        local relative_dir
        # remove filename from path, so only directory path stays
        relative_dir="$(dirname "$relative_path")"

        local target_dir
        # relative_dir will be "." if file is present in source folder
        if [[ "$relative_dir" == "." ]]; then
            # file will be placed directly inside backup folder
            target_dir="$backup_dir"
        else
            # file will be placed at relative path with backup directory as head-directory
            target_dir="$backup_dir/$relative_dir"
        fi

        # create all missing parent-directories
        # -p blocks possible errors, if files already exist
        mkdir -p "$target_dir"

        # save the current file according to the protocoll provided in save_file to this path (target_dir)
        save_file "$file" "$target_dir"

        # $? contains exit status of command executed immediatly before
        local status=$?

        # every file processed in loop counts in total 
        total=$((total + 1))

        case "$status" in 
            0) 
                # source file was unchanged; no new backup necessary
                ((skipped++))
                ;;
            2) 
                # source file was new or changed; new .phbs-container was created
                ((changed++))
                ;;
            *)
                # every other return values is treated as error
                ((errors++))
                ;;
        esac

    # has sth. to do with process substitution so, loop will be running in current shell and not always in new shells    
    
    # searching through source directory (find works recursively)
    # -type f means, only normale files (f), directoryies will not be worked with
    # -print0: typically find will separate files with returns, which can cause errors, so -print0 separates files with a NUL-Byte
    # result will be returned like a file
    # first < means: take file as input for while-loop
    # second < means: process substitution: makes output of find to sth like a file
    done < <(find "$source_dir" -type f -print0)

    # save curretn Unix timestamp after backup finished
    local end_time
    end_time=$(date +%s%3N)
    local duration
    duration=$((end_time - start_time))

    # pass all collected statistics to log_backup()
    log_backup \
        "$source_dir" \
        "$backup_dir" \
        "$total" \
        "$changed" \
        "$skipped" \
        "$errors" \
        "$duration"
    
    #display summary
    echo ""
    header "Backup finished"
    field "Files:"    "$total"
    field "Changed:"  "$changed" "$C_GREEN"
    field "Skipped:"  "$skipped" "$C_GRAY"
    if (( errors > 0 )); then
        field "Errors:" "$errors" "$C_RED"
    else
        field "Errors:" "$errors"
    fi
    field "Duration:" "${duration}ms" "$C_CYAN"

    # if there was an error with a single file, the parentfunction shall also return an error
    if (( errors > 0 )); then
        return 1
    fi

    return 0
}


save_file() {
    # defining parameters as local variables
    local source="$1"
    local backup_dir="$2"

    # is provided file a existing normal file?
    if [[ ! -f "$source" ]]; then
        error "File not found: $source"

        # return 1 menas that an error occurred
        # this status will later be counted by save_folder()
        return 1
    fi

    # creates backup-directory (just to make shure it exists)
    mkdir -p "$backup_dir"

    local filename
    # basename removes path of file, which leaves only the name of the file
    filename=$(basename "$source")

    # %. removes the file ending
    # .phbs adds the new file ending (container format for phobos backup files)
    local container_name="${filename%.*}.phbs"
    local container="$backup_dir/$container_name"

    local original_size
    # stat reads informations about files
    # -c '%s', returns size of file in bytes
    original_size=$(stat -c '%s' "$source")

    local source_hash
    # xxhsum generates hash value for the file
    # | (pipe) takes results and hands them over to awk
    # normally xxhsum return sth like a7fe... ./.../file.txt, so $1 takes only hash-value
    source_hash=$(xxhsum "$source" | awk '{print $1}')

    # checks if a backup of the file already exists
    if [[ -f "$container" ]]; then

        local header_size
        # reading header size from existing backup
        header_size=$(head -c 8 "$container")

        # checks if the header size contains only numbers
        if [[ "$header_size" =~ ^[0-9]+$ ]]; then
            # converting bytes to decimal number
            header_size=$((10#$header_size))

            local header
            # reads the header from the existing container
            # skip=9: first 9 bytes wll be skipped because they contain the header size and the newline char
            header=$(dd if="$container" bs=1 skip=9 count="$header_size" 2>/dev/null)

            local backup_hash
            # reads the stored hash from the existing header
            backup_hash=$(printf '%s\n' "$header" |
                grep '^HASH=' |
                cut -d= -f2-)

            # compares hash of source file with hash stored in backup
            # if hashes are identically there is no need for a new backup
            if [[ "$source_hash" == "$backup_hash" ]]; then
                info "Unchanged: $source"
                # return 0 means that the file was successfully checked
                # but no new backup was necessary because the file is unchanged
                # save_folder() uses this status to increase "skipped" counter
                return 0
            fi
        fi
    fi

    info "Sichere: $source"

    local compressed
    #mktemp creates temorary file
    compressed=$(mktemp)


    local compression_type

    if should_compress "$source"; then
        # compresses file 
        # -c: write compressed file to stdout instead of changing original file
        # result is pushed to temporary file by using '>'
        gzip -c "$source" > "$compressed"
        compression_type="gzip"
    else 
        cp "$source" "$compressed"
        compression_type="none"
    fi 


    # building custom header for .phbs files
    # VERSION of container-format, if it will be updated in the future
    # HASH of uncompressed originale file
    # COMPRESSION states the type of compression 
    # FILENAME saves original filename
    # ORIGINAL_SIZE saves originale size of file

    local header
    header="PHBS
VERSION=1
HASH=$source_hash
COMPRESSION=$compression_type
FILENAME=$filename
ORIGINAL_SIZE=$original_size"

    local header_size
    # calculating amout of bytes for header
    # printf ... returns header and adds additional newline
    # wc -c: counts bytes 
    header_size=$(printf '%s\n' "$header" | wc -c)
    # curly brackets group multiply commands
    {
        # prints header size as a int (%d) with 8 figures and fills missing places with 0
        printf '%08d\n' "$header_size"
        # prints header
        printf '%s\n' "$header"
        # add the compressed file
        cat "$compressed"
    } > "$container"
    # remvoe temporary file
    rm -f "$compressed"

    success "Erstellt: $container"
    # retunr 2 means, file was successfully backed up 
    # either because the backup did nit exist yet
    # or because source file had changed
    # save_folder() uses this status to increase the "changed" counter
    return 2
}