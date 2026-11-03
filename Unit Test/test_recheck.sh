#!/bin/bash
# Tests for recheck_selected_device (last-moment refusal of the boot drive and the Ventoy USB).
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$REPO_ROOT/lib/logging.sh"
source "$REPO_ROOT/lib/drives.sh"
echo "test_recheck"
LOG_FILE=""; DEBUG=false
load_fns "$REPO_ROOT/dr_usb_create.sh" recheck_selected_device
log_message() { echo "$1"; }
lsblk() { printf '%b' "$LSOUT"; }
chk() { LSOUT="$1"; recheck_selected_device /dev/x >/dev/null 2>&1; echo $?; }
assert_eq "UNRAID label refused" "1" "$(chk 'NAME="sdb1" LABEL="UNRAID" MOUNTPOINT="/boot"\n')"
assert_eq "/boot mount with empty label refused" "1" "$(chk 'NAME="sdb1" LABEL="" MOUNTPOINT="/boot"\n')"
assert_eq "Ventoy label refused" "1" "$(chk 'NAME="sde1" LABEL="Ventoy" MOUNTPOINT=""\n')"
assert_eq "VTOYEFI label refused" "1" "$(chk 'NAME="sde1" LABEL="Ventoy" MOUNTPOINT=""\nNAME="sde2" LABEL="VTOYEFI" MOUNTPOINT=""\n')"
assert_eq "used drive allowed" "0" "$(chk 'NAME="sdd1" LABEL="BACKUP" MOUNTPOINT=""\nNAME="sdd2" LABEL="" MOUNTPOINT=""\n')"
assert_eq "blank drive allowed" "0" "$(chk 'NAME="sdc" LABEL="" MOUNTPOINT=""\n')"
finish
