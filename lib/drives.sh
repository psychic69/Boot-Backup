#!/bin/bash
# lib/drives.sh - lsblk drive-state helpers
# Shared module for dr_usb_backup.sh and dr_usb_create.sh.
# Sourced by those scripts; not meant to be run directly.

# --- Convert Bytes to Human Readable Function ---
convert_bytes_to_human() {
    local bytes="$1"
    if [[ -z "$bytes" ]] || ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        echo "0.00G (0 bytes)"
        return
    fi
    local gigabytes=$(awk "BEGIN {printf \"%.2f\", $bytes / (1024 * 1024 * 1024)}")
    echo "${gigabytes}G (${bytes} bytes)"
}

# --- Function to load the lsblk data ---
load_drive_state() {
    if [ "$USE_TEST_FILE" = true ]; then
        log_message "INFO: Using test-lsblk file for drive state (synthetic testing mode)..."
        if [ ! -f "./test-lsblk" ]; then
            log_message "ERROR: Test file './test-lsblk' not found"
            return 1
        fi
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                current_drive_state+=("$line")
                debug_print "Loaded drive state line: $line"
            fi
        done < "./test-lsblk"
        if [ ${#current_drive_state[@]} -eq 0 ]; then
            log_message "ERROR: No drive data loaded from test-lsblk file"
            return 1
        fi
        log_message "INFO: Loaded ${#current_drive_state[@]} drive entries from test-lsblk file"
    else
        log_message "INFO: Loading current drive state from lsblk..."
        local lsblk_output
        if ! lsblk_output=$(lsblk -b -P -o NAME,UUID,FSTYPE,SIZE,MOUNTPOINT,LABEL,TRAN 2>&1); then
            log_message "ERROR: Failed to execute lsblk command"
            log_message "ERROR: lsblk output: $lsblk_output"
            return 1
        fi
        debug_print "lsblk command executed successfully"
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                current_drive_state+=("$line")
            fi
        done <<< "$lsblk_output"
        if [ ${#current_drive_state[@]} -eq 0 ]; then
            log_message "ERROR: No drive data loaded from lsblk"
            return 1
        fi
        log_message "INFO: Loaded ${#current_drive_state[@]} drive entries from lsblk"
    fi
    return 0
}

# --- Function to get column value from a key=value pair line ---
get_column_value() {
    local row="$1"
    local column_name="$2"
    local pattern="${column_name}=\"([^\"]*)\""
    if [[ $row =~ $pattern ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# --- Function to get TRAN type from parent device ---
get_tran_type() {
    local current_index="$1"
    local current_name=$(get_column_value "${current_drive_state[$current_index]}" "NAME")
    local base_device=$(echo "$current_name" | sed 's/[0-9]*$//' | sed 's/p$//')
    local i
    debug_print "Current name: $current_name"
    debug_print "Looking for base device: $base_device"
    debug_print "Starting from index: $current_index"
    for ((i=current_index-1; i>=0; i--)); do
        local check_row="${current_drive_state[$i]}"
        local check_name=$(get_column_value "$check_row" "NAME")
        local check_tran=$(get_column_value "$check_row" "TRAN")
        debug_print "Checking index $i: name='$check_name' tran='$check_tran'"
        if [[ "$check_name" == "$base_device" ]]; then
            debug_print "Found parent device with TRAN='$check_tran'"
            echo "$check_tran"
            return
        fi
    done
    debug_print "No parent device found"
    echo ""
}

# --- Function to print partition state ---
print_partition_state() {
    local row="$1"
    local row_index="$2"
    local name=$(get_column_value "$row" "NAME")
    local mountpoint=$(get_column_value "$row" "MOUNTPOINT")
    local uuid=$(get_column_value "$row" "UUID")
    local fstype=$(get_column_value "$row" "FSTYPE")
    local label=$(get_column_value "$row" "LABEL")
    local size=$(get_column_value "$row" "SIZE")
    local tran=$(get_column_value "$row" "TRAN")
    if [[ -z "$tran" ]]; then
        tran=$(get_tran_type "$row_index")
    fi
    local size_human=$(convert_bytes_to_human "$size")
    local drive_location="$name"
    if [[ "$name" =~ ^(sd[a-z][0-9]+|nvme[0-9]+n[0-9]+p[0-9]+|md[0-9]+p[0-9]+) ]]; then
        drive_location="/dev/$name"
    fi
    log_message "  Drive location: $drive_location"
    log_message "  Current Mountpoint: $mountpoint"
    log_message "  UUID: $uuid"
    log_message "  File type: $fstype"
    log_message "  Current Label: $label"
    log_message "  Drive Size: $size_human"
    log_message "  Transport Type: $tran"
    log_message ""
}
