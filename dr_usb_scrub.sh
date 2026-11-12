#!/bin/bash

# dr_usb_scrub.sh - maintenance scrub: checks the Unraid boot files for damage.
#
# Always checks the live Unraid flash drive (/boot and /boot/previous) against the .sha256 files
# Unraid ships. With -backup it also checks the local UNRAID_DR USB (the same hash checks the restore
# script does, plus the DR_MANIFEST.sums written by dr_usb_backup.sh).
#
# The backup is for disaster recovery, not a perfect sync: config changes since the last backup are
# expected and are NEVER reported. Only damaged or missing boot files are.
#
# Schedule it separately from the backup, as maintenance (weekly or monthly). A full scrub reads
# roughly 2-3 GB from each side being checked.
# Exit code 0 = clean, 1 = problems found (details are in the output and in the log).

# Global variables
declare -a current_drive_state
declare -a FINDINGS      # "where|name|problem|expected|actual|size"
declare -a WARNINGS
DEBUG=false
USE_TEST_FILE=false
CHECK_BACKUP=false
LOG_FILE=""
BOOT_DIR="/boot"          # the Unraid flash drive; only the tests change this

# Handle argument parsing for both User Scripts (passes path or "" as $1) and standalone execution.
if [[ $# -gt 0 ]] && [[ "$1" != -* ]]; then
    shift
fi
while [[ $# -gt 0 ]]; do
    case $1 in
        -backup)
            CHECK_BACKUP=true
            shift
            ;;
        -debug)
            DEBUG=true
            shift
            ;;
        -lsblk)
            USE_TEST_FILE=true
            shift
            ;;
        *)
            echo "Unknown option: \"$1\""
            echo "Usage: $0 [-backup] [-debug] [-lsblk]"
            exit 1
            ;;
    esac
done

#===============================================
# SHARED MODULES (lib/) AND SETTINGS
#===============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
for _lib in logging drives integrity config; do
    if [ ! -f "${LIB_DIR}/${_lib}.sh" ]; then
        echo "FATAL: Missing module ${LIB_DIR}/${_lib}.sh" >&2
        echo "FATAL: Install the full release archive into /boot/config/plugins/dr_usb/ and run the script from there." >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "${LIB_DIR}/${_lib}.sh"
done
unset _lib

# --- Record every entry of HASH_FAILURES as a finding for <where> ---
add_hash_findings() {
    local where="$1" entry
    for entry in "${HASH_FAILURES[@]}"; do
        FINDINGS+=("${where}|${entry}")
    done
}

# --- Make the checks read the real flash drive, not RAM ---
# Files read recently (by a backup, for example) stay in the Linux page cache, so hashing them would test RAM and
# could miss damage on the drive. lib/integrity.sh evicts each file's cached pages just before hashing it.
HASH_BYPASS_CACHE=true
CACHE_BYPASS_FAILED=false
report_cache_bypass() {
    if [ "$CACHE_BYPASS_FAILED" = true ]; then
        log_message "WARNING: Could not bypass the file cache for some files (needs GNU dd); a clean result may reflect RAM rather than the drive."
    else
        log_message "INFO: Each file was read from the drive itself (its cached copy was dropped first), not from RAM."
    fi
}

# --- Step 1: the live Unraid flash drive ---
scrub_live() {
    log_message "INFO: ===== CHECKING THE LIVE UNRAID FLASH DRIVE (${BOOT_DIR}) ====="
    if ! mountpoint -q "${BOOT_DIR}" 2>/dev/null; then
        log_message "ERROR: ${BOOT_DIR} is not mounted, so the live flash drive could not be checked."
        FINDINGS+=("LIVE ${BOOT_DIR}|${BOOT_DIR}|IS NOT MOUNTED|||")
        return 1
    fi
    CACHE_BYPASS_FAILED=false
    local rc=0
    verify_boot_hashes "${BOOT_DIR}" || rc=1
    report_cache_bypass
    if [ "$rc" -ne 0 ]; then
        add_hash_findings "LIVE ${BOOT_DIR}"
        return 1
    fi
    return 0
}

# --- Step 2a: the local UNRAID_DR USB ---
scrub_local_backup() {
    log_message "INFO: ===== CHECKING THE LOCAL BACKUP USB (UNRAID_DR) ====="
    load_drive_state || { FINDINGS+=("BACKUP USB|-|COULD NOT READ THE DRIVE LIST|||"); return 1; }

    local -a parts=()
    local i row label name tran
    for i in "${!current_drive_state[@]}"; do
        row="${current_drive_state[$i]}"
        label=$(get_column_value "$row" "LABEL")
        [[ "$label" == "UNRAID_DR" ]] || continue
        name=$(get_column_value "$row" "NAME")
        tran=$(get_column_value "$row" "TRAN")
        [[ -n "$tran" ]] || tran=$(get_tran_type "$i")
        [[ "$tran" == "usb" ]] || continue
        parts+=("$name")
    done
    if [ ${#parts[@]} -ne 1 ]; then
        log_message "ERROR: Expected exactly one USB drive labelled UNRAID_DR, found ${#parts[@]}."
        FINDINGS+=("BACKUP USB|UNRAID_DR|EXPECTED ONE UNRAID_DR USB DRIVE, FOUND ${#parts[@]}|||")
        return 1
    fi

    local device="/dev/${parts[0]}"
    local mp mounted_here=false
    mp=$(findmnt -n -o TARGET "$device" 2>/dev/null | head -n 1)
    if [ -n "$mp" ]; then
        log_message "INFO: ${device} is already mounted at ${mp}; reading from there."
    else
        mp="$CLONE_MP"
        mkdir -p "$mp" 2>/dev/null
        if ! run_logged "mount" mount -o ro "$device" "$mp"; then
            log_message "ERROR: Could not mount ${device} read-only at ${mp}."
            FINDINGS+=("BACKUP USB|${device}|COULD NOT BE MOUNTED|||")
            return 1
        fi
        mounted_here=true
    fi

    CACHE_BYPASS_FAILED=false
    local problems=0
    if ! verify_boot_hashes "$mp"; then
        add_hash_findings "BACKUP USB"
        problems=1
    fi
    verify_backup_manifest_dir "$mp"
    case $? in
        1) add_hash_findings "BACKUP USB"; problems=1 ;;
        2) WARNINGS+=("The backup USB has no ${BACKUP_MANIFEST_NAME}: config/ and the other small files were not checked (it is written by the next local backup).") ;;
    esac
    report_cache_bypass

    if [ "$mounted_here" = true ]; then
        run_logged "umount" umount "$mp" || log_message "WARNING: Could not unmount ${mp}."
    fi
    [ "$problems" -eq 0 ]
}

# --- Final report: loud and specific when anything is wrong ---
report_results() {
    local w count=${#FINDINGS[@]}
    for w in "${WARNINGS[@]}"; do
        log_message "WARNING: ${w}"
    done
    if [ "$count" -eq 0 ]; then
        log_message "INFO: ==============================================================="
        log_message "INFO:  SCRUB CLEAN - no problems found."
        log_message "INFO: ==============================================================="
        return 0
    fi

    local bar="################################################################################"
    log_message "ERROR: ${bar}"
    log_message "ERROR: ##  SCRUB FAILED - ${count} PROBLEM(S) FOUND"
    log_message "ERROR: ${bar}"
    local entry where name problem expected actual size last_where=""
    for entry in "${FINDINGS[@]}"; do
        IFS='|' read -r where name problem expected actual size <<< "$entry"
        log_message "ERROR: [${where}]  ${name}"
        log_message "ERROR:     problem : ${problem}"
        [ -n "$expected" ] && log_message "ERROR:     expected: ${expected}"
        [ -n "$actual" ]   && log_message "ERROR:     actual  : ${actual}"
        [ -n "$size" ]     && log_message "ERROR:     size    : ${size} bytes"
    done
    log_message "ERROR: ${bar}"
    log_message "ERROR: WHAT TO DO:"
    local seen=" "
    for entry in "${FINDINGS[@]}"; do
        where="${entry%%|*}"
        case "$seen" in *" $where "*) continue ;; esac
        seen="${seen}${where} "
        case "$where" in
            LIVE*)
                log_message "ERROR:  - ${where}: your RUNNING Unraid flash drive has damaged or missing boot files."
                log_message "ERROR:    The backup will refuse to run (it will not overwrite a good backup with damaged files)."
                log_message "ERROR:    Copy /boot somewhere safe now, then replace or re-image the flash drive from your last good backup." ;;
            "BACKUP USB")
                log_message "ERROR:  - BACKUP USB: the UNRAID_DR copy is damaged or incomplete, so it may not restore properly."
                log_message "ERROR:    If the live drive is fine, delete the named file(s) from the backup USB (or re-run dr_usb_create.sh)"
                log_message "ERROR:    and run dr_usb_backup.sh: rsync will not replace a damaged file whose size and date still match." ;;
        esac
    done
    notify_failure "Scrub found ${count} problem(s) with your Unraid boot files or backup. See log: ${LOG_FILE}"
    return 1
}

main_scrub() {
    local mode="live /boot only"
    if [ "$CHECK_BACKUP" = true ]; then
        mode="live /boot + the LOCAL UNRAID_DR USB"
    fi
    log_message "INFO: Starting UNRAID DR **SCRUB** (${mode})"

    scrub_live
    if [ "$CHECK_BACKUP" = true ]; then
        scrub_local_backup
    fi
    report_results
}

####################MAIN CODE EXECUTION

if ! load_config; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Could not load settings. Exiting." >&2
    exit 1
fi
if ! validate_parameters; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Parameter validation failed. Exiting." >&2
    exit 1
fi
if ! setup_logging "scrub"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Failed to setup logging. Exiting." >&2
    exit 1
fi
file_rotation "${LOG_DIR}/logs" "scrub-*.log" "$((SNAPSHOTS * 2))" "${RETENTION_DAYS}"

main_scrub
scrub_rc=$?
if [ $scrub_rc -ne 0 ]; then
    log_message "ERROR: UNRAID DR **SCRUB** finished: PROBLEMS FOUND (exit $scrub_rc)."
else
    log_message "INFO: UNRAID DR **SCRUB** finished: clean."
fi
exit $scrub_rc
