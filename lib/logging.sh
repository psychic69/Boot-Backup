#!/bin/bash
# lib/logging.sh - logging helpers
# Shared module for dr_usb_backup.sh and dr_usb_create.sh.
# Sourced by those scripts; not meant to be run directly.

# --- Logging Function ---
# A simple function to log messages to a specified file and to the console.
log_message() {
    local message="$1"
    if [[ -z "${LOG_FILE}" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - UNINITIALIZED_LOG - ${message}" >&2
        return
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ${message}" | tee -a "${LOG_FILE}"
}

# --- Logging Setup Function ---
# Initializes the logging environment.
setup_logging() {
    local prefix="${1:-boot-check}"
    local log_dir="${LOG_DIR}/logs"
    if [ ! -d "${LOG_DIR}" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO: Base log location '${LOG_DIR}' does not exist. Attempting to create it." >&2
        if ! mkdir -p "${LOG_DIR}"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Failed to create base log location '${LOG_DIR}'. Cannot setup logging." >&2
            return 1
        fi
    fi
    if [ ! -w "${LOG_DIR}" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Base log location '${LOG_DIR}' is not writable. Cannot setup logging." >&2
        return 1
    fi
    if ! mkdir -p "${log_dir}"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Failed to create log directory '${log_dir}'." >&2
        return 1
    fi
    if [ ! -w "${log_dir}" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Log directory '${log_dir}' is not writable." >&2
        return 1
    fi
    LOG_FILE="${log_dir}/${prefix}-$(date '+%Y-%m-%d_%H%M%S').log"
    if ! touch "${LOG_FILE}"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Could not create log file at '${LOG_FILE}'." >&2
        LOG_FILE=""
        return 1
    fi
    return 0
}

# --- File Rotation Function ---
# Rotates files based on age (retention days) and count (snapshots).
file_rotation() {
    local dir="$1"
    local pattern="$2"
    local max_files="$3"
    local retention_days="$4"
    log_message "INFO: Checking retention policy for pattern '${pattern}' in '${dir}'. Max age: ${retention_days} days."
    find "${dir}" -maxdepth 1 -type f -name "${pattern}" -mtime "+$((retention_days - 1))" | while read -r old_file; do
        log_message "INFO: Deleting file due to retention policy (> ${retention_days} days): '${old_file}'"
        if ! rm -f "${old_file}"; then
            log_message "WARNING: Failed to delete retention-expired file '${old_file}'."
        fi
    done
    log_message "INFO: Checking item count for pattern '${pattern}' in '${dir}'. Max files to keep: ${max_files}."
    local current_file_count
    current_file_count=$(find "${dir}" -maxdepth 1 -type f -name "${pattern}" | wc -l)
    if (( current_file_count > max_files )); then
        local num_to_delete=$((current_file_count - max_files))
        log_message "INFO: Found ${current_file_count} files, which exceeds max of ${max_files}. Deleting the ${num_to_delete} oldest file(s)."
        find "${dir}" -maxdepth 1 -type f -name "${pattern}" -printf '%T@ %p\n' | sort -n | head -n "${num_to_delete}" | cut -d' ' -f2- | while read -r old_file; do
            log_message "INFO: Deleting oldest item to meet count limit: '${old_file}'"
            if ! rm -f "${old_file}"; then
                log_message "WARNING: Failed to delete old item file '${old_file}'."
            fi
        done
    else
        log_message "INFO: ${current_file_count} file(s) found. No count-based rotation needed for pattern '${pattern}'."
    fi
    return 0
}

# --- Debug print function ---
debug_print() {
    if [ "$DEBUG" = true ]; then
        log_message "DEBUG: $*"
    fi
}

# --- Run a command, log its output at DEBUG level, and return the COMMAND's exit status ---
# (Piping straight into "while read" would return the loop's status and hide failures.)
run_logged() {
    local label="$1"; shift
    local out rc line
    out=$("$@" 2>&1)
    rc=$?
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        if [ $rc -ne 0 ]; then
            log_message "ERROR: $label: $line"
        else
            debug_print "$label: $line"
        fi
    done <<< "$out"
    return $rc
}

# --- Remove earlier logs that finished successfully ---
# Usage: remove_old_successful_logs <dir> <name-pattern> <log-to-keep> <success-marker>
# Used by dr_usb_create.sh: once a new log exists, older logs whose run ended successfully
# are deleted; logs from failed runs are kept for diagnosis.
remove_old_successful_logs() {
    local dir="$1" pattern="$2" keep="$3" marker="$4" old_file
    while IFS= read -r old_file; do
        [ -n "${old_file}" ] || continue
        [ "${old_file}" = "${keep}" ] && continue
        if grep -qF -- "${marker}" "${old_file}" 2>/dev/null; then
            log_message "INFO: Removing earlier successful log: '${old_file}'"
            if ! rm -f "${old_file}"; then
                log_message "WARNING: Failed to delete earlier log '${old_file}'."
            fi
        fi
    done < <(find "${dir}" -maxdepth 1 -type f -name "${pattern}" 2>/dev/null)
    return 0
}

# --- Send an Unraid GUI notification on failure (remote mode) ---
notify_failure() {
    [ "$NOTIFY_ON_FAILURE" = true ] || return 0
    local notify="/usr/local/emhttp/webGui/scripts/notify"
    [ -x "$notify" ] || return 0
    "$notify" -e "DR USB Backup" -s "Remote boot backup FAILED" -d "$1" -i alert >/dev/null 2>&1 || true
}
