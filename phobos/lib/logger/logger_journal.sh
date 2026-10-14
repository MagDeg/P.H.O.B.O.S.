#!/bin/bash
#
# PHOBOS Logger - journal entry point.
#
# Reads journal lines (one per line) from stdin and routes each through the
# journal collectors. A single line may also be passed as the first argument,
# which is what `phobos logger ingest <line>` uses.
#
# The service installed by `phobos logger enable` runs:
#   journalctl -f -o short -n 0 | logger_journal.sh

# allow overriding, e.g. for development ($LIB_DIR/logger/...)
LIB_DIR="${LIB_DIR:-/usr/local/lib/phobos}"

source "$LIB_DIR/style.sh"
source "$LIB_DIR/logger/storage.sh"
source "$LIB_DIR/logger/logger.sh"
source "$LIB_DIR/logger/validation.sh"
source "$LIB_DIR/logger/collector.sh"

# single line mode
if [[ $# -gt 0 ]]; then
    logger_collect_journal_line "$1"
    exit $?
fi

# stream mode: consume journal lines until the pipe closes
while IFS= read -r line; do
    logger_collect_journal_line "$line"
done

exit 0
