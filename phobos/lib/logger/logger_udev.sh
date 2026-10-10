#!/bin/bash

LIB_DIR="/usr/local/lib/phobos"

source "$LIB_DIR/logger/storage.sh"
source "$LIB_DIR/logger/security.sh"
source "$LIB_DIR/logger/logger.sh"
source "$LIB_DIR/logger/collector.sh"

logger_collect_udev