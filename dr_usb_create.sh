#!/bin/bash

#===============================================
# INTERACTIVE SCRIPT CHECK
# This script is interactive and must be run from a TTY (SSH session).
# It cannot be run from the Unraid User Scripts plugin.
#===============================================
if [ ! -t 1 ]; then
    echo "FATAL: This script (dr_usb_create.sh) is interactive and must be run from an SSH terminal." >&2
    echo "FATAL: Please SSH into your Unraid server and run this script manually." >&2
    echo "FATAL: For scheduled backups, use dr_usb_backup.sh." >&2
    exit 1
fi

# Global variables
declare -a current_drive_state
declare -a clone_array
DEBUG=false
USE_TEST_FILE=false
LOG_FILE=""
BOOT_SIZE=""
CLONE_DEVICE=""

# Handle argument parsing
# This script is run from CLI, so parsing is simple.
while [[ $# -gt 0 ]]; do
    case $1 in
        -debug)
            DEBUG=true
            shift
            ;;
        -lsblk)
            USE_TEST_FILE=true
            shift
            ;;
        *)
            # Use quotes around "$1" to properly display empty strings
            echo "Unknown option: \"$1\""
            echo "Usage: $0 [-debug] [-lsblk]"
            exit 1
            ;;
    esac
done

#===============================================
# USER CONFIGURATION - EDIT THESE VALUES
#===============================================

# LOG_DIR: Absolute path to the directory where logs will be stored.
LOG_DIR="/boot/logs/unraid-dr"

# SNAPSHOTS: Number of log files to keep (must be >= 1).
SNAPSHOTS=10
 
# RETENTION_DAYS: Number of days to retain log files (must be >= 1).
RETENTION_DAYS=30

# CLONE_MP: Absolute path to a temporary mount point for the backup USB.
CLONE_MP="/mnt/disks/usb-backup-temp"

#===============================================
# END OF USER CONFIGURATION
# (Do not edit below this line)
#===============================================

# --- Logging Function ---
log_message() {
    local message="$1"
    if [[ -z "${LOG_FILE}" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - UNINITIALIZED_LOG - ${message}" | tee -a /tmp/dr_usb_create.log >&2
        return
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ${message}" | tee -a "${LOG_FILE}"
}

# --- Logging Setup Function ---
setup_logging() {
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
    LOG_FILE="${log_dir}/boot-check-$(date '+%Y-%m-%d_%H%M%S').log"
    if ! touch "${LOG_FILE}"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Could not create log file at '${LOG_FILE}'." >&2
        LOG_FILE=""
        return 1
    fi
    local max_logs=$((SNAPSHOTS * 2))
    file_rotation "${log_dir}" "boot-check-*.log" "${max_logs}" "${RETENTION_DAYS}"
    return 0
}

# --- Validate Parameters Function ---
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
    if [ $error_count -gt 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: $error_count configuration error(s) found. Please correct them in the script." >&2
        return 1
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO: Parameters validated successfully." >&2
    return 0
}

# --- File Rotation Function ---
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

# --- Debug print function ---
debug_print() {
    if [ "$DEBUG" = true ]; then
        log_message "DEBUG: $*"
    fi
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

# --- Partition Device Function ---
partition_device_new() {
    local device="$1"
    if [ -z "${device}" ]; then
        log_message "ERROR: No device specified for partitioning."
        return 1
    fi
    debug_print "partition_device_new called with device: ${device}"
    if [ ! -b "${device}" ]; then
        log_message "ERROR: Device ${device} is not a valid block device."
        return 1
    fi
    debug_print "Device ${device} validated as block device"
    log_message "INFO: Checking drive size for ${device}..."
    local drive_size_bytes=$(lsblk -b -n -d -o SIZE ${device})
    if [ -z "${drive_size_bytes}" ]; then
        log_message "ERROR: Could not determine size of ${device}"
        return 1
    fi
    debug_print "Drive size in bytes: ${drive_size_bytes}"
    local max_size_bytes=$((64 * 1024 * 1024 * 1024))
    debug_print "Maximum partition size: ${max_size_bytes} bytes (64GB)"
    local sfdisk_partition_def=""
    if [ "${drive_size_bytes}" -gt "${max_size_bytes}" ]; then
        log_message "INFO: Drive is larger than 64GB. Creating a 64GB partition."
        sfdisk_partition_def="size=64G, type=b"
    else
        log_message "INFO: Drive is 64GB or smaller. Using the entire drive."
        sfdisk_partition_def="type=b"
    fi
    debug_print "Partition definition: ${sfdisk_partition_def}"
    log_message "INFO: Wiping existing signatures and creating new partition on ${device}..."
    debug_print "Running wipefs -a ${device}"
    if ! wipefs -a "${device}" 2>&1 | while IFS= read -r line; do debug_print "wipefs: $line"; done; then
        log_message "WARNING: wipefs encountered issues, but continuing..."
    fi
    debug_print "Running sfdisk ${device} with definition: ${sfdisk_partition_def}"
    if ! echo "${sfdisk_partition_def}" | sfdisk "${device}" 2>&1 | while IFS= read -r line; do debug_print "sfdisk: $line"; done; then
        log_message "ERROR: Failed to partition ${device} with sfdisk"
        return 1
    fi
    log_message "INFO: Partition table created successfully"
    debug_print "Running partprobe ${device}"
    if ! partprobe "${device}" 2>&1 | while IFS= read -r line; do debug_print "partprobe: $line"; done; then
        log_message "WARNING: partprobe encountered issues, but continuing..."
    fi
    debug_print "Sleeping 2 seconds to allow device node creation"
    sleep 2
    local partition="${device}1"
    debug_print "Partition to format: ${partition}"
    if [ ! -b "${partition}" ]; then
        log_message "ERROR: Partition ${partition} was not created successfully"
        return 1
    fi
    log_message "INFO: Formatting ${partition} as VFAT (FAT32)..."
    debug_print "Running mkfs.vfat -F 32 -n UNRAID_DR ${partition}"
    if ! mkfs.vfat -F 32 -n "UNRAID_DR" ${partition} 2>&1 | while IFS= read -r line; do debug_print "mkfs.vfat: $line"; done; then
        log_message "ERROR: Failed to format ${partition} as VFAT"
        return 1
    fi
    log_message "INFO: Process complete. ${device} is partitioned, formatted, and labeled 'UNRAID_DR'."
    return 0
}

# --- Function to find and prepare clone drive (INTERACTIVE) ---
find_and_prepare_clone() {
    log_message "INFO: No UNRAID_DR partition found. Searching for suitable USB drives..."
    local min_required_size=$(awk "BEGIN {printf \"%.0f\", $BOOT_SIZE * 0.95}")
    local boot_size_human=$(convert_bytes_to_human "$BOOT_SIZE")
    debug_print "Boot size: $BOOT_SIZE bytes"
    debug_print "Minimum required size (95%): $min_required_size bytes"
    declare -a qualified_devices
    declare -a qualified_models
    declare -a qualified_sizes
    for i in "${!current_drive_state[@]}"; do
        local row="${current_drive_state[$i]}"
        local name=$(get_column_value "$row" "NAME")
        local label=$(get_column_value "$row" "LABEL")
        local uuid=$(get_column_value "$row" "UUID")
        local size=$(get_column_value "$row" "SIZE")
        if [[ "$name" =~ [0-9]$ ]] && [[ -n "$label" ]]; then
            debug_print "Checking partition: name='$name' label='$label'"
            if [[ "$label" == "UNRAID" ]]; then
                debug_print "Skipping UNRAID partition: $name"
                continue
            fi
            local parent_device=$(echo "$name" | sed 's/[0-9]*$//' | sed 's/p$//')
            debug_print "Parent device for $name: $parent_device"
            local parent_row=""
            local parent_size=""
            local parent_tran=""
            for j in "${!current_drive_state[@]}"; do
                local check_row="${current_drive_state[$j]}"
                local check_name=$(get_column_value "$check_row" "NAME")
                if [[ "$check_name" == "$parent_device" ]]; then
                    parent_row="$check_row"
                    parent_size=$(get_column_value "$check_row" "SIZE")
                    parent_tran=$(get_column_value "$check_row" "TRAN")
                    debug_print "Found parent device: $check_name with TRAN=$parent_tran and SIZE=$parent_size"
                    break
                fi
            done
            if [[ "$parent_tran" != "usb" ]]; then
                debug_print "Parent device $parent_device is not USB (TRAN=$parent_tran), skipping"
                continue
            fi
            debug_print "Found USB partition: $name with label '$label' on parent $parent_device"
            if [[ -n "$parent_size" ]] && [[ "$parent_size" =~ ^[0-9]+$ ]] && (( parent_size >= min_required_size )); then
                log_message "INFO: Qualified USB drive found: /dev/$parent_device (partition: /dev/$name, label: $label)"
                clone_array+=("$parent_row")
                local model=$(lsblk -n -d -o MODEL "/dev/$parent_device" 2>/dev/null | xargs)
                if [[ -z "$model" ]]; then
                    model="Unknown"
                fi
                qualified_devices+=("$parent_device")
                qualified_models+=("$model")
                qualified_sizes+=("$parent_size")
                log_message "INFO: Partition table for /dev/$parent_device:"
                fdisk -l "/dev/$parent_device" 2>&1 | while IFS= read -r line; do
                    log_message "  $line"
                done
                log_message "INFO: Disk information for /dev/$parent_device:"
                log_message "  Parent Device: $parent_device"
                log_message "  Model: $model"
                log_message "  Partition: $name"
                log_message "  Partition Label: $label"
                log_message "  Partition UUID: $uuid"
                log_message "  Parent Size: $(convert_bytes_to_human "$parent_size")"
                log_message "  Transport: $parent_tran"
                log_message ""
            else
                local drive_size_human=$(convert_bytes_to_human "$parent_size")
                log_message "INFO: USB Drive /dev/$parent_device (label: $label) is too small to be used as a backup. Size must be 95% or greater of $boot_size_human. Current size: $drive_size_human"
            fi
        fi
    done
    if [ ${#clone_array[@]} -eq 0 ]; then
        log_message "ERROR: There were no qualified USB available backup drives found. Please connect a new drive."
        exit 1
    fi
    log_message "INFO: Found ${#qualified_devices[@]} qualified USB drive(s) for backup."
    log_message ""
    log_message "=========================================="
    log_message "Here are the qualified drive(s) to format to be the backup USB for the /boot system."
    log_message "Choose the drive you would like. Please type in the device name from the list:"
    log_message "=========================================="
    log_message ""
    for i in "${!qualified_devices[@]}"; do
        local size_human=$(convert_bytes_to_human "${qualified_sizes[$i]}")
        log_message "  Device Name: ${qualified_devices[$i]}"
        log_message "  Model: ${qualified_models[$i]}"
        log_message "  Size: $size_human"
        log_message ""
    done
    local selected_device=""
    local attempt=0
    local max_attempts=2
    while [ $attempt -lt $max_attempts ]; do
        echo -n "Enter device name (e.g., sdh): "
        read selected_device
        debug_print "User entered device: '$selected_device'"
        local device_found=false
        for device in "${qualified_devices[@]}"; do
            if [[ "$device" == "$selected_device" ]]; then
                device_found=true
                break
            fi
        done
        if [ "$device_found" = true ]; then
            log_message "INFO: Device $selected_device selected."
            break
        else
            ((attempt++))
            if [ $attempt -lt $max_attempts ]; then
                log_message "ERROR: Device '$selected_device' is not in the qualified list. Please try again."
            else
                log_message "ERROR: Device '$selected_device' is not in the qualified list. Maximum attempts reached."
                log_message "ERROR: Exiting script."
                exit 1
            fi
        fi
    done
    log_message ""
    log_message "=========================================="
    log_message "WARNING: Be aware the device /dev/$selected_device will be formatted and wiped."
    log_message "WARNING: All data on this device will be permanently lost!"
    log_message "=========================================="
    log_message "Are you sure you want to do this? If so, type FORMAT in all capitals:"
    log_message ""
    local confirmation=""
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        echo -n "Type FORMAT to confirm: "
        read confirmation
        debug_print "User entered confirmation: '$confirmation'"
        if [[ "$confirmation" == "FORMAT" ]]; then
            log_message "INFO: Confirmation received. Proceeding with formatting."
            break
        else
            ((attempt++))
            if [ $attempt -lt $max_attempts ]; then
                log_message "ERROR: Incorrect confirmation. Please type FORMAT in all capitals."
            else
                log_message "ERROR: Incorrect confirmation. Maximum attempts reached."
                log_message "ERROR: Exiting script."
                exit 1
            fi
        fi
    done
    log_message ""
    log_message "INFO: Starting partitioning and formatting of /dev/$selected_device..."
    if ! partition_device_new "/dev/$selected_device"; then
        log_message "FATAL: Failed to partition and format /dev/$selected_device"
        exit 1
    fi
    CLONE_DEVICE="/dev/$selected_device"
    log_message "INFO: CLONE_DEVICE set to: $CLONE_DEVICE"
    debug_print "Global CLONE_DEVICE: $CLONE_DEVICE"
    log_message "INFO: Executing initial clone_backup with device: $CLONE_DEVICE"
    clone_backup "$CLONE_DEVICE"
}

# --- Function to perform clone backup ---
clone_backup() {
    local clone_device="$1"
    if [ -z "$clone_device" ]; then
        log_message "ERROR: No clone device provided to clone_backup function"
        return 1
    fi
    log_message "INFO: Starting clone backup process for device: $clone_device"
    debug_print "clone_backup called with device: $clone_device"
    local clone_source="${clone_device}1"
    debug_print "Clone source partition set to: $clone_source"
    if [ ! -b "$clone_source" ]; then
        log_message "ERROR: Clone source partition $clone_source does not exist as a block device"
        return 1
    fi
    log_message "INFO: Clone source partition: $clone_source"
    local clone_mounted_already="FALSE"
    local current_mount_point=""
    current_mount_point=$(findmnt -n -o TARGET "$clone_source" 2>/dev/null)
    if [ -n "$current_mount_point" ]; then
        log_message "INFO: $clone_source is already mounted at: $current_mount_point"
        local mount_options=$(findmnt -n -o OPTIONS "$clone_source" 2>/dev/null)
        debug_print "Mount options: $mount_options"
        local first_option=$(echo "$mount_options" | cut -d',' -f1)
        debug_print "First mount option: $first_option"
        if [[ "$first_option" == "rw" ]]; then
            log_message "INFO: $clone_source is mounted read/write"
            CLONE_MP="$current_mount_point"
            clone_mounted_already="TRUE"
            debug_print "Using existing mount point: $CLONE_MP"
        else
            log_message "WARNING: $clone_source is mounted read-only (first option: $first_option). Unmounting..."
            if ! umount "$clone_source" 2>&1 | while IFS= read -r line; do debug_print "umount: $line"; done; then
                log_message "ERROR: Failed to unmount $clone_source, attempting force unmount..."
                if ! umount -f "$clone_source" 2>&1 | while IFS= read -r line; do debug_print "umount -f: $line"; done; then
                    log_message "ERROR: Failed to force unmount $clone_source"
                    return 1
                fi
            fi
            log_message "INFO: Successfully unmounted $clone_source"
        fi
    fi
    if [ "$clone_mounted_already" != "TRUE" ]; then
        log_message "INFO: Mounting $clone_source at $CLONE_MP..."
        if [ ! -d "$CLONE_MP" ]; then
            debug_print "Creating mount point directory: $CLONE_MP"
            if ! mkdir -p "$CLONE_MP"; then
                log_message "ERROR: Failed to create mount point directory: $CLONE_MP"
                return 1
            fi
        fi
        if [ ! -w "$CLONE_MP" ]; then
            log_message "ERROR: Mount point directory $CLONE_MP is not writable"
            return 1
        fi
        debug_print "Mount point directory verified: $CLONE_MP"
        if ! mount "$clone_source" "$CLONE_MP" 2>&1 | while IFS= read -r line; do debug_print "mount: $line"; done; then
            log_message "ERROR: Failed to mount $clone_source at $CLONE_MP"
            return 1
        fi
        log_message "INFO: Successfully mounted $clone_source at $CLONE_MP"
        local mount_options=$(findmnt -n -o OPTIONS "$clone_source" 2>/dev/null)
        debug_print "Checking mount options after mount: $mount_options"
        local first_option=$(echo "$mount_options" | cut -d',' -f1)
        debug_print "First mount option: $first_option"
        if [[ "$first_option" == "rw" ]]; then
            log_message "INFO: Mount verified as read/write"
        else
            log_message "ERROR: Device mounted but not read/write. First option: $first_option, Full options: $mount_options"
            umount "$CLONE_MP"
            return 1
        fi
    fi
    log_message "INFO: Verifying /boot is mounted..."
    if ! mountpoint -q /boot; then
        log_message "ERROR: /boot is not mounted"
        if [ "$clone_mounted_already" != "TRUE" ]; then
            umount "$CLONE_MP"
        fi
        return 1
    fi
    log_message "INFO: /boot is correctly mounted"
    log_message "INFO: Starting rsync backup from /boot/ to $CLONE_MP/"
    local rsync_cmd="rsync -ah"
    if [ "$DEBUG" = true ]; then
        rsync_cmd="$rsync_cmd -v --dry-run"
        log_message "INFO: DEBUG MODE - Running rsync with --dry-run (no actual changes)"
    fi
    rsync_cmd="$rsync_cmd /boot/ $CLONE_MP/"
    debug_print "Rsync command: $rsync_cmd"
    log_message "INFO: Executing: $rsync_cmd"
    if ! eval "$rsync_cmd" 2>&1 | while IFS= read -r line; do log_message "  rsync: $line"; done; then
        log_message "ERROR: Rsync backup failed"
        if [ "$clone_mounted_already" != "TRUE" ]; then
            umount "$CLONE_MP"
        fi
        return 1
    fi
    log_message "INFO: Rsync backup completed successfully"
    log_message "INFO: Checking for old BACKUP-* marker files in $CLONE_MP..."
    local backup_files_found=false
    while IFS= read -r backup_file; do
        if [ -n "$backup_file" ]; then
            backup_files_found=true
            log_message "INFO: Deleting old backup marker: $backup_file"
            debug_print "Removing file: $backup_file"
            if [ "$DEBUG" != true ]; then
                rm -f "$backup_file"
            else
                log_message "INFO: DEBUG MODE - Would delete: $backup_file"
            fi
        fi
    done < <(find "$CLONE_MP" -maxdepth 1 -type f -name "BACKUP-*" 2>/dev/null)
    if [ "$backup_files_found" = false ]; then
        log_message "INFO: No old BACKUP-* marker files found"
    fi
    local timestamp=$(date '+%m-%d-%Y-%H-%M')
    local backup_marker="$CLONE_MP/BACKUP-$timestamp"
    log_message "INFO: Creating backup marker file: BACKUP-$timestamp"
    debug_print "Touch file: $backup_marker"
    if [ "$DEBUG" != true ]; then
        if ! touch "$backup_marker"; then
            log_message "ERROR: Failed to create backup marker file: $backup_marker"
            if [ "$clone_mounted_already" != "TRUE" ]; then
                umount "$CLONE_MP"
            fi
            return 1
        fi
    else
        log_message "INFO: DEBUG MODE - Would create: $backup_marker"
    fi
    log_message "INFO: Backup marker created successfully"
    log_message "INFO: Disabling EFI boot to prevent accidental boot from backup..."
    local efi_dir="$CLONE_MP/EFI"
    local efi_disabled_dir="$CLONE_MP/EFI-"
    if [ -d "$efi_dir" ]; then
        log_message "INFO: Found EFI directory, renaming to EFI-"
        debug_print "Moving $efi_dir to $efi_disabled_dir"
        if [ "$DEBUG" != true ]; then
            if [ -d "$efi_disabled_dir" ]; then
                debug_print "Removing existing EFI- directory"
                rm -rf "$efi_disabled_dir"
            fi
            if ! mv "$efi_dir" "$efi_disabled_dir"; then
                log_message "ERROR: Failed to rename EFI directory"
                if [ "$clone_mounted_already" != "TRUE" ]; then
                    umount "$CLONE_MP"
                fi
                return 1
            fi
            if [ -d "$efi_disabled_dir" ] && [ ! -d "$efi_dir" ]; then
                log_message "INFO: EFI directory successfully renamed to EFI-"
            else
                log_message "ERROR: EFI directory rename verification failed"
                return 1
            fi
        else
            log_message "INFO: DEBUG MODE - Would rename $efi_dir to $efi_disabled_dir"
        fi
    else
        log_message "INFO: No EFI directory found, skipping EFI disable step"
    fi
    if [ "$clone_mounted_already" != "TRUE" ]; then
        log_message "INFO: Unmounting $clone_source from $CLONE_MP..."
        debug_print "Unmounting: $clone_source"
        if [ "$DEBUG" != true ]; then
            if ! umount "$CLONE_MP" 2>&1 | while IFS= read -r line; do debug_print "umount: $line"; done; then
                log_message "ERROR: Failed to unmount $clone_source"
                return 1
            fi
            if mountpoint -q "$CLONE_MP"; then
                log_message "ERROR: Device still appears to be mounted after unmount attempt"
                return 1
            fi
            log_message "INFO: Successfully unmounted $clone_source"
        else
            log_message "INFO: DEBUG MODE - Would unmount $clone_source"
        fi
    else
        log_message "INFO: Leaving $clone_source mounted (was already mounted before backup)"
    fi
    log_message "INFO: Clone backup process completed successfully"
    return 0
}

# --- Main function (Create) ---
main_create() {
    # Load the drive state
    if ! load_drive_state; then
        log_message "FATAL: Failed to load drive state"
        exit 1
    fi
    
    # Find all partitions with LABEL "UNRAID" where NAME ends in "1"
    local -a unraid_partitions
    local -a unraid_indices
    for i in "${!current_drive_state[@]}"; do
        local row="${current_drive_state[$i]}"
        local label=$(get_column_value "$row" "LABEL")
        local name=$(get_column_value "$row" "NAME")
        if [[ "$label" == "UNRAID" ]] && [[ "$name" =~ 1$ ]]; then
            debug_print "Found UNRAID partition: $name"
            unraid_partitions+=("$row")
            unraid_indices+=("$i")
        fi
    done
    
    # Check if we have exactly one UNRAID partition
    if [ ${#unraid_partitions[@]} -ne 1 ]; then
        log_message "ERROR: You have multiple partitions with the label: UNRAID. You must only have one or the system may not boot properly. Please resolve"
        log_message ""
        for idx in "${!unraid_partitions[@]}"; do
            print_partition_state "${unraid_partitions[$idx]}" "${unraid_indices[$idx]}"
        done
        exit 1
    fi
    
    # We have exactly one UNRAID partition
    local boot_row="${unraid_partitions[0]}"
    local boot_mount=$(get_column_value "$boot_row" "MOUNTPOINT")
    BOOT_SIZE=$(get_column_value "$boot_row" "SIZE")
    
    # Validate that boot_mount is /boot
    if [[ "$boot_mount" != "/boot" ]]; then
        log_message "FATAL: UNRAID partition is not mounted at /boot. Current mount point: '$boot_mount'"
        exit 1
    fi
    
    log_message "INFO: The current booted environment is as follows"
    log_message ""
    print_partition_state "${unraid_partitions[0]}" "${unraid_indices[0]}"
    debug_print "Boot size set to: $BOOT_SIZE bytes"
    
    # Scan for UNRAID_DR partition
    local clone_found=false
    for i in "${!current_drive_state[@]}"; do
        local row="${current_drive_state[$i]}"
        local label=$(get_column_value "$row" "LABEL")
        if [[ "$label" == "UNRAID_DR" ]]; then
            clone_found=true
            break
        fi
    done
    
    # Main logic fork for this script
    if [ "$clone_found" = true ]; then
        log_message "ERROR: An 'UNRAID_DR' partition was already found."
        log_message "ERROR: This create script is only for the first-time setup."
        log_message "ERROR: If you want to run a backup, use the 'dr_usb_backup.sh' script."
        log_message "ERROR: If you want to create a NEW drive, you must first remove the 'UNRAID_DR' label from the existing one."
        exit 1
    else
        # No UNRAID_DR partition found, go through device selection and formatting
        log_message "INFO: No 'UNRAID_DR' partition found. Proceeding with interactive setup..."
        find_and_prepare_clone
    fi
}

######MAIN CODE EXECUTION

# First, validate parameters. This must be run before logging is set up.
if ! validate_parameters; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Parameter validation failed. Exiting." >&2
    exit 1
fi

# Initialize logging using the validated parameters
if ! setup_logging; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Failed to setup logging. Exiting." >&2
    exit 1
fi

log_message "INFO: Starting UNRAID DR USB **CREATE** script (Interactive)"
log_message "INFO: Configuration parameters:"
log_message "INFO:   LOG_DIR=$LOG_DIR"
log_message "INFO:   SNAPSHOTS=$SNAPSHOTS"
log_message "INFO:   RETENTION_DAYS=$RETENTION_DAYS"
log_message "INFO:   CLONE_MP=$CLONE_MP"

# Run the main function
main_create

log_message "INFO: UNRAID DR USB **CREATE** script completed."