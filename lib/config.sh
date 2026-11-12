#!/bin/bash
# lib/config.sh - settings and validation
# Shared module for dr_usb_backup.sh and dr_usb_create.sh.
# Sourced by those scripts; not meant to be run directly.

# --- Load settings: defaults first, then the optional dr_usb.ini beside the scripts ---
# Copy dr_usb.ini.example to dr_usb.ini to change any value; an upgrade never overwrites dr_usb.ini.
# Requires SCRIPT_DIR to be set by the calling script.
load_config() {
    LOG_DIR="/boot/logs/unraid-dr"
    SNAPSHOTS=10
    RETENTION_DAYS=30
    CLONE_MP="/mnt/disks/usb-backup-temp"
    NOTIFY_ON_FAILURE=true
    DR_USB_INI="${DR_USB_INI:-${SCRIPT_DIR}/dr_usb.ini}"
    DR_USB_INI_LOADED=false
    if [ -f "${DR_USB_INI}" ]; then
        # shellcheck source=/dev/null
        if ! source "${DR_USB_INI}"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Failed to read settings file ${DR_USB_INI}" >&2
            return 1
        fi
        DR_USB_INI_LOADED=true
    fi
    return 0
}

# --- Validate Parameters Function ---
# Validates the configuration parameters.
validate_parameters() {
    local error_count=0
    if [ -z "$LOG_DIR" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: LOG_DIR is not defined in the script's configuration block." >&2
        ((error_count++))
    elif [[ ! "$LOG_DIR" =~ ^/ ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: LOG_DIR must be an absolute path starting with '/'. Got: $LOG_DIR" >&2
        ((error_count++))
    fi
    if [ -z "$SNAPSHOTS" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: SNAPSHOTS is not defined." >&2
        ((error_count++))
    elif ! [[ "$SNAPSHOTS" =~ ^[0-9]+$ ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: SNAPSHOTS must be a number. Got: $SNAPSHOTS" >&2
        ((error_count++))
    elif [ "$SNAPSHOTS" -lt 1 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: SNAPSHOTS must be greater than or equal to 1. Got: $SNAPSHOTS" >&2
        ((error_count++))
    fi
    if [ -z "$RETENTION_DAYS" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: RETENTION_DAYS is not defined." >&2
        ((error_count++))
    elif ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: RETENTION_DAYS must be a number. Got: $RETENTION_DAYS" >&2
        ((error_count++))
    elif [ "$RETENTION_DAYS" -lt 1 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: RETENTION_DAYS must be greater than or equal to 1. Got: $RETENTION_DAYS" >&2
        ((error_count++))
    fi
    if [ -z "$CLONE_MP" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: CLONE_MP is not defined." >&2
        ((error_count++))
    elif [[ ! "$CLONE_MP" =~ ^/ ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: CLONE_MP must be an absolute path starting with '/'. Got: $CLONE_MP" >&2
        ((error_count++))
    fi
    if [ "$NOTIFY_ON_FAILURE" != true ] && [ "$NOTIFY_ON_FAILURE" != false ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: NOTIFY_ON_FAILURE must be true or false. Got: $NOTIFY_ON_FAILURE" >&2
        ((error_count++))
    fi
    if [ $error_count -gt 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: $error_count configuration error(s) found. Please correct them in the script." >&2
        return 1
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO: Parameters validated successfully." >&2
    return 0
}
