#!/bin/bash
#
# PHOBOS Logger - udev entry point.
#
# udev invokes this script directly (via the rule installed by
# `phobos logger enable`). It re-sources the logger libraries and dispatches
# the current udev event through the registered udev collectors.

LIB_DIR="${LIB_DIR:-/usr/local/lib/phobos}"

source "$LIB_DIR/logger/storage.sh"
source "$LIB_DIR/logger/logger.sh"
source "$LIB_DIR/logger/validation.sh"
source "$LIB_DIR/logger/collector.sh"

logger_collect_udev
