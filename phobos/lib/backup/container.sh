# reads meta-data from .phbs files
container_info() {
    #defining parameters as local variables
    local container="$1" # path to .phbs-container

    # checking if .phsb-file exits
    if [[ ! -f "$container" ]]; then
        error "File not found: $container"
        return 1
    fi

    local header_size
    # reading first 8 bytes of header as header size
    header_size=$(head -c 8 "$container")

    # validating header size using REGEX, so only numbers are contained
    if ! [[ "$header_size" =~ ^[0-9]+$ ]]; then
        error "Invalid PHBS-Container."
        return 1
    fi

    # converting header size to decimal number
    header_size=$((10#$header_size))

    local header
    # reading header from byte 10
    header=$(dd if="$container" bs=1 skip=9 count="$header_size" 2>/dev/null)

    # checking if container is phbs-container
    if ! grep -q "^PHBS$" <<< "$header"; then
        error "Invalid PHBS-Container."
        return 1
    fi

    local version
    local hash
    local compression
    local filename
    local original_size

    # reading values from header
    version=$(grep '^VERSION=' <<< "$header" | cut -d= -f2-)
    hash=$(grep '^HASH=' <<< "$header" | cut -d= -f2-)
    compression=$(grep '^COMPRESSION=' <<< "$header" | cut -d= -f2-)
    filename=$(grep '^FILENAME=' <<< "$header" | cut -d= -f2-)
    original_size=$(grep '^ORIGINAL_SIZE=' <<< "$header" | cut -d= -f2-)

    local container_size
    # calculating size of container
    container_size=$(stat -c '%s' "$container")

    local compressed_size
    # calculating compressed size (subtracting the not-payload-ares from container size)
    compressed_size=$((container_size - header_size - 9))

    # Ausgabe
    header "PHBS Container"
    field "Version:"         "$version" "$C_CYAN"
    field "Filename:"        "$filename"
    field "Compression:"     "$compression"
    field "Hash:"            "$hash" "$C_GRAY"
    field "Original Size:"   "${original_size} bytes"
    field "Compressed Size:" "${compressed_size} bytes"

    # calculating compression rate
    # only if orignal file is not empty
    if (( original_size > 0 )); then
        local compression_percent
        # -v : hand values over to awk
        # printf "%.1f" : floating point number with exactly 1 number after decimal point ist printed
        compression_percent=$(awk \
            -v original="$original_size" \
            -v compressed="$compressed_size" \
            'BEGIN { printf "%.1f", (1 - compressed / original) * 100 }')

        # print compression rate
        field "Compression Rate:" "${compression_percent}%" "$C_GREEN"
    fi
}