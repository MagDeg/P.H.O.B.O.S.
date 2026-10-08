# const variable for versioning
readonly VERSION="0.0.2"

# contains file types that are already compressed, so there is no need to compress them again
readonly NO_COMPRESS_EXTENSIONS=(
    jpg jpeg png gif webp avif heic
    mp4 mkv avi mov webm
    mp3 flac wav ogg aac
    zip rar 7z gt bz2 xz zst
    pdf
)