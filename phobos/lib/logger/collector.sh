#!/bin/bash

# collector entry point.  
# sources every per-channel collector in collector/. 
#   drive/udev -> collector_drive.sh  
#   auth       -> collector_auth.sh
#   sudo       -> collector_sudo.sh  
#   journal    -> collector_journal.sh (router)  
#   audit      -> collector_audit.sh 

# locate the collector/ directory next to this file, independent of cwd.  
collector_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/collector" 

source "$collector_dir/collector_drive.sh"  
source "$collector_dir/collector_auth.sh" 
source "$collector_dir/collector_sudo.sh" 
source "$collector_dir/collector_journal.sh"
source "$collector_dir/collector_audit.sh"  
source "$collector_dir/collector_user.sh" 
source "$collector_dir/collector_system.sh" 
source "$collector_dir/collector_network.sh" 
source "$collector_dir/collector_process.sh"  

unset collector_dir 
