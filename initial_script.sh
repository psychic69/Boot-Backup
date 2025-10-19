#!/bin/bash

# Global variables
declare -a current_drive_state
declare -a clone_array
DEBUG=false
LOG_FILE=""
LOG_DIR="/var/log/unraid-boot-check"
SNAPSHOTS=5
RETENTION_DAYS=30
BOOT_UUID=""
BOOT_MOUNT=""
BOOT_SIZE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -debug)
            DEBUG=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [-debug]"
            exit 1
            ;;
    esac
done

# --- Logging Function ---
# A simple function to log messages to a specified file and to the console.
# Relies on the global LOG_FILE variable being set by setup_logging().
#
# @param {string} Message - The message to be logged.
log_message() {
    local message="$1"
    # Fallback to stderr if logging has not been initialized.
    if [[ -z "${LOG_FILE}" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - UNINITIALIZED_LOG - ${message}" >&2
        return
    fi
    # Logs the message with a timestamp to both the console and the log file.
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ${message}" | tee -a "${LOG_FILE}"
}

# --- Logging Setup Function ---
# Initializes the logging environment, creates the log directory, and sets the
# log file for the current run.
#
# @uses global LOG_DIR
# @uses global SNAPSHOTS
# @uses global LOG_FILE
# @return {integer} 0 for success, 1 for failure.
setup_logging() {
    local log_dir="${LOG_DIR}/logs"

    # First, try to create the base LOG_DIR if it doesn't exist.
    if [ ! -d "${LOG_DIR}" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO: Base log location '${LOG_DIR}' does not exist. Attempting to create it." >&2
        if ! mkdir -p "${LOG_DIR}"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Failed to create base log location '${LOG_DIR}'. Cannot setup logging." >&2
            return 1
        fi
    fi

    # Verify the base LOG_DIR is writable.
    if [ ! -w "${LOG_DIR}" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Base log location '${LOG_DIR}' is not writable. Cannot setup logging." >&2
        return 1
    fi

    # Create the log directory if it doesn't exist.
    if ! mkdir -p "${log_dir}"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Failed to create log directory '${log_dir}'." >&2
        return 1
    fi

    # Verify the log directory is writable.
    if [ ! -w "${log_dir}" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Log directory '${log_dir}' is not writable." >&2
        return 1
    fi

    # Set the global LOG_FILE variable for this script execution.
    LOG_FILE="${log_dir}/boot-check-$(date '+%Y-%m-%d_%H%M%S').log"
    
    # Create the log file immediately and check for success.
    if ! touch "${LOG_FILE}"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Could not create log file at '${LOG_FILE}'." >&2
        LOG_FILE=""
        return 1
    fi

    # Call the dedicated file rotation function for the logs.
    local max_logs=$((SNAPSHOTS * 2))
    file_rotation "${log_dir}" "boot-check-*.log" "${max_logs}" "${RETENTION_DAYS}"

    return 0
}

# --- File Rotation Function ---
# Rotates files based on age (retention days) and count (snapshots).
#
# @param {string} dir - The directory containing the files.
# @param {string} pattern - The file pattern to match (e.g., "*.log").
# @param {integer} max_files - The maximum number of files to keep by count.
# @param {integer} retention_days - The maximum age in days for files.
# @return {integer} 0 for success.
file_rotation() {
    local dir="$1"
    local pattern="$2"
    local max_files="$3"
    local retention_days="$4"

    # --- 1. Retention Policy Deletion (by age) ---
    log_message "INFO: Checking retention policy for pattern '${pattern}' in '${dir}'. Max age: ${retention_days} days."
    # Use find with -mtime to locate files older than retention_days and delete them.
    # -mtime +N finds files modified more than N+1 days ago, so +$((retention_days - 1)) is correct.
    find "${dir}" -maxdepth 1 -type f -name "${pattern}" -mtime "+$((retention_days - 1))" | while read -r old_file; do
        log_message "INFO: Deleting file due to retention policy (> ${retention_days} days): '${old_file}'"
        if ! rm -f "${old_file}"; then
            log_message "WARNING: Failed to delete retention-expired file '${old_file}'."
        fi
    done

    # --- 2. Snapshot Count Rotation (by count) ---
    log_message "INFO: Checking item count for pattern '${pattern}' in '${dir}'. Max files to keep: ${max_files}."
    
    local current_file_count
    current_file_count=$(find "${dir}" -maxdepth 1 -type f -name "${pattern}" | wc -l)

    if (( current_file_count > max_files )); then
        local num_to_delete=$((current_file_count - max_files))
        log_message "INFO: Found ${current_file_count} files, which exceeds max of ${max_files}. Deleting the ${num_to_delete} oldest file(s)."
        
        # List remaining files by modification time (oldest first) and delete the excess.
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
# Converts a size value in bytes to gigabytes with 2 decimal precision.
#
# @param {string} size - The size in bytes (e.g., "8053063680")
# @return {string} Human readable format: "XX.XXG (YYYY bytes)"
convert_bytes_to_human() {
    local bytes="$1"
    
    # Check if bytes is empty or not a number
    if [[ -z "$bytes" ]] || ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        echo "0.00G (0 bytes)"
        return
    fi
    
    # Convert bytes to gigabytes with 2 decimal precision using awk
    local gigabytes=$(awk "BEGIN {printf \"%.2f\", $bytes / (1024 * 1024 * 1024)}")
    
    echo "${gigabytes}G (${bytes} bytes)"
}

# Debug print function
debug_print() {
    if [ "$DEBUG" = true ]; then
        log_message "DEBUG: $*"
    fi
}

# Function to load the lsblk data
load_drive_state() {
    while IFS= read -r line; do
        current_drive_state+=("$line")
    done < "./test-lsblk"
}

# Function to get column value from a key=value pair line
get_column_value() {
    local row="$1"
    local column_name="$2"
    
    # Extract value using parameter expansion
    local pattern="${column_name}=\"([^\"]*)\""
    if [[ $row =~ $pattern ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# Function to get TRAN type from parent device
get_tran_type() {
    local current_index="$1"
    local current_name=$(get_column_value "${current_drive_state[$current_index]}" "NAME")
    
    # Extract the base device name (e.g., sda from sda1, nvme0n1 from nvme0n1p1)
    local base_device=$(echo "$current_name" | sed 's/[0-9]*$//' | sed 's/p$//')
    
    debug_print "Current name: $current_name"
    debug_print "Looking for base device: $base_device"
    debug_print "Starting from index: $current_index"
    
    # Search backwards for the parent device
    for ((i=current_index-1; i>=0; i--)); do
        local check_row="${current_drive_state[$i]}"
        local check_name=$(get_column_value "$check_row" "NAME")
        local check_tran=$(get_column_value "$check_row" "TRAN")
        
        debug_print "Checking index $i: name='$check_name' tran='$check_tran'"
        
        # If we find the parent device (matches base name)
        if [[ "$check_name" == "$base_device" ]]; then
            debug_print "Found parent device with TRAN='$check_tran'"
            echo "$check_tran"
            return
        fi
    done
    
    debug_print "No parent device found"
    echo ""
}

# Function to print partition state
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
    
    # If TRAN is empty, get it from parent device
    if [[ -z "$tran" ]]; then
        tran=$(get_tran_type "$row_index")
    fi
    
    # Convert size to human readable format with bytes
    local size_human=$(convert_bytes_to_human "$size")
    
    # Prepend /dev/ if it's a device partition
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
# Partitions and formats a device as FAT32 with label UNRAID_DR
# If drive > 64GB, creates a 64GB partition. Otherwise uses entire drive.
#
# @param {string} device - The device to partition (e.g., /dev/sdh)
# @return {integer} 0 for success, 1 for failure.
partition_device_new() {
    local device="$1"
    
    # --- INPUT VALIDATION ---
    if [ -z "${device}" ]; then
        log_message "ERROR: No device specified for partitioning."
        log_message "Usage: partition_device_new /dev/sdX"
        return 1
    fi
    
    debug_print "partition_device_new called with device: ${device}"
    
    if [ ! -b "${device}" ]; then
        log_message "ERROR: Device ${device} is not a valid block device."
        log_message "Please use a command like 'lsblk' to verify the device name."
        return 1
    fi
    
    debug_print "Device ${device} validated as block device"
    
    # --- CHECK DRIVE SIZE & PREPARE PARTITION DEFINITION ---
    log_message "INFO: Checking drive size for ${device}..."
    
    # Get the total size of the drive in bytes.
    local drive_size_bytes=$(lsblk -b -n -d -o SIZE ${device})
    
    if [ -z "${drive_size_bytes}" ]; then
        log_message "ERROR: Could not determine size of ${device}"
        return 1
    fi
    
    debug_print "Drive size in bytes: ${drive_size_bytes}"
    
    # Define our maximum size: 64 GiB in bytes (64 * 1024^3).
    local max_size_bytes=$((64 * 1024 * 1024 * 1024))
    
    debug_print "Maximum partition size: ${max_size_bytes} bytes (64GB)"
    
    # Variable to hold the partition definition for sfdisk.
    local sfdisk_partition_def=""
    
    if [ "${drive_size_bytes}" -gt "${max_size_bytes}" ]; then
        log_message "INFO: Drive is larger than 64GB. Creating a 64GB partition."
        # Define a partition of 64GB with type 'b' (W95 FAT32).
        sfdisk_partition_def="size=64G, type=b"
    else
        log_message "INFO: Drive is 64GB or smaller. Using the entire drive."
        # Define a single partition of type 'b' using all available space.
        sfdisk_partition_def="type=b"
    fi
    
    debug_print "Partition definition: ${sfdisk_partition_def}"
    
    # --- PARTITION THE DRIVE ---
    log_message "INFO: Wiping existing signatures and creating new partition on ${device}..."
    
    # First, wipe any existing filesystem or partition table signatures.
    debug_print "Running wipefs -a ${device}"
    if ! wipefs -a "${device}" 2>&1 | while IFS= read -r line; do debug_print "wipefs: $line"; done; then
        log_message "WARNING: wipefs encountered issues, but continuing..."
    fi
    
    # Use sfdisk to create the MBR partition table and partition in one step.
    debug_print "Running sfdisk ${device} with definition: ${sfdisk_partition_def}"
    if ! echo "${sfdisk_partition_def}" | sfdisk "${device}" 2>&1 | while IFS= read -r line; do debug_print "sfdisk: $line"; done; then
        log_message "ERROR: Failed to partition ${device} with sfdisk"
        return 1
    fi
    
    log_message "INFO: Partition table created successfully"
    
    # Use partprobe to make sure the kernel recognizes the new partition table.
    debug_print "Running partprobe ${device}"
    if ! partprobe "${device}" 2>&1 | while IFS= read -r line; do debug_print "partprobe: $line"; done; then
        log_message "WARNING: partprobe encountered issues, but continuing..."
    fi
    
    # Short pause to ensure the device node is created.
    debug_print "Sleeping 2 seconds to allow device node creation"
    sleep 2
    
    # --- FORMAT THE PARTITION ---
    # The new partition will be the device name followed by the number '1'.
    local partition="${device}1"
    
    debug_print "Partition to format: ${partition}"
    
    if [ ! -b "${partition}" ]; then
        log_message "ERROR: Partition ${partition} was not created successfully"
        return 1
    fi
    
    log_message "INFO: Formatting ${partition} as VFAT (FAT32)..."
    
    # The -n flag sets the volume name (label) to UNRAID_DR.
    debug_print "Running mkfs.vfat -F 32 -n UNRAID_DR ${partition}"
    if ! mkfs.vfat -F 32 -n "UNRAID_DR" ${partition} 2>&1 | while IFS= read -r line; do debug_print "mkfs.vfat: $line"; done; then
        log_message "ERROR: Failed to format ${partition} as VFAT"
        return 1
    fi
    
    log_message "INFO: Process complete. ${device} is partitioned, formatted, and labeled 'UNRAID_DR'."
    
    return 0
}

# Function to find and prepare clone drive
# Function to find and prepare clone drive
find_and_prepare_clone() {
    log_message "INFO: No UNRAID_DR partition found. Searching for suitable USB drives..."
    
    # Calculate minimum required size (95% of boot size)
    local min_required_size=$(awk "BEGIN {printf \"%.0f\", $BOOT_SIZE * 0.95}")
    local boot_size_human=$(convert_bytes_to_human "$BOOT_SIZE")
    
    debug_print "Boot size: $BOOT_SIZE bytes"
    debug_print "Minimum required size (95%): $min_required_size bytes"
    
    # Arrays to store qualified drive information
    declare -a qualified_devices
    declare -a qualified_models
    declare -a qualified_sizes
    
    # Scan for USB drives by looking at partitions first
    for i in "${!current_drive_state[@]}"; do
        local row="${current_drive_state[$i]}"
        local name=$(get_column_value "$row" "NAME")
        local label=$(get_column_value "$row" "LABEL")
        local uuid=$(get_column_value "$row" "UUID")
        local size=$(get_column_value "$row" "SIZE")
        
        # Check if this is a partition (name ends with a number) with a label
        if [[ "$name" =~ [0-9]$ ]] && [[ -n "$label" ]]; then
            debug_print "Checking partition: name='$name' label='$label'"
            
            # Skip if label is UNRAID
            if [[ "$label" == "UNRAID" ]]; then
                debug_print "Skipping UNRAID partition: $name"
                continue
            fi
            
            # Extract the parent device name (e.g., sda from sda1, nvme0n1 from nvme0n1p1)
            local parent_device=$(echo "$name" | sed 's/[0-9]*$//' | sed 's/p$//')
            
            debug_print "Parent device for $name: $parent_device"
            
            # Find the parent device row to get TRAN and SIZE
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
            
            # Check if parent is USB
            if [[ "$parent_tran" != "usb" ]]; then
                debug_print "Parent device $parent_device is not USB (TRAN=$parent_tran), skipping"
                continue
            fi
            
            debug_print "Found USB partition: $name with label '$label' on parent $parent_device"
            
            # Check if parent device size meets minimum requirement
            if [[ -n "$parent_size" ]] && [[ "$parent_size" =~ ^[0-9]+$ ]] && (( parent_size >= min_required_size )); then
                log_message "INFO: Qualified USB drive found: /dev/$parent_device (partition: /dev/$name, label: $label)"
                
                # Add parent device row to clone_array
                clone_array+=("$parent_row")
                
                # Get model information from lsblk
                local model=$(lsblk -n -d -o MODEL "/dev/$parent_device" 2>/dev/null | xargs)
                if [[ -z "$model" ]]; then
                    model="Unknown"
                fi
                
                # Store qualified drive information
                qualified_devices+=("$parent_device")
                qualified_models+=("$model")
                qualified_sizes+=("$parent_size")
                
                # Print partition table information for parent device
                log_message "INFO: Partition table for /dev/$parent_device:"
                fdisk -l "/dev/$parent_device" 2>&1 | while IFS= read -r line; do
                    log_message "  $line"
                done
                
                # Print disk information
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
    
    # Check if we found any qualified drives
    if [ ${#clone_array[@]} -eq 0 ]; then
        log_message "ERROR: There were no qualified USB available backup drives found. Please connect a new drive."
        exit 1
    fi
    
    log_message "INFO: Found ${#qualified_devices[@]} qualified USB drive(s) for backup."
    log_message ""
    
    # Display menu of qualified drives
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
    
    # Prompt user for device selection (two attempts)
    local selected_device=""
    local attempt=0
    local max_attempts=2
    
    while [ $attempt -lt $max_attempts ]; do
        echo -n "Enter device name (e.g., sdh): "
        read selected_device
        
        debug_print "User entered device: '$selected_device'"
        
        # Check if the entered device is in the qualified list
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
    
    # Prompt user for confirmation (two attempts)
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
    
    # Execute partition_device_new function
    log_message "INFO: Starting partitioning and formatting of /dev/$selected_device..."
    if ! partition_device_new "/dev/$selected_device"; then
        log_message "FATAL: Failed to partition and format /dev/$selected_device"
        exit 1
    fi
    
    # Set global variable
    CLONE_DEVICE="/dev/$selected_device"
    log_message "INFO: CLONE_DEVICE set to: $CLONE_DEVICE"
    debug_print "Global CLONE_DEVICE: $CLONE_DEVICE"
    
    # Execute clone_backup function
    log_message "INFO: Executing clone_backup with device: $CLONE_DEVICE"
    clone_backup "$CLONE_DEVICE"
}

# Function to perform clone backup
clone_backup() {
    log_message "INFO: UNRAID_DR partition found. Proceeding with backup..."
    # TODO: Implement clone backup logic
}

# Main function
initial_test() {
    # Load the drive state
    load_drive_state
    
    # Find all partitions with LABEL "UNRAID" where NAME ends in "1"
    local -a unraid_partitions
    local -a unraid_indices
    
    for i in "${!current_drive_state[@]}"; do
        local row="${current_drive_state[$i]}"
        local label=$(get_column_value "$row" "LABEL")
        local name=$(get_column_value "$row" "NAME")
        
        debug_print "Checking row $i: name='$name' label='$label'"
        
        # Check if label is UNRAID and name ends in 1
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
    # Extract and store boot partition information
    local boot_row="${unraid_partitions[0]}"
    BOOT_UUID=$(get_column_value "$boot_row" "UUID")
    BOOT_MOUNT=$(get_column_value "$boot_row" "MOUNTPOINT")
    BOOT_SIZE=$(get_column_value "$boot_row" "SIZE")
    
    # Validate that BOOT_MOUNT is /boot
    if [[ "$BOOT_MOUNT" != "/boot" ]]; then
        log_message "FATAL: UNRAID partition is not mounted at /boot. Current mount point: '$BOOT_MOUNT'"
        log_message "The UNRAID boot partition must be mounted at /boot for the system to function correctly."
        log_message ""
        print_partition_state "${unraid_partitions[0]}" "${unraid_indices[0]}"
        exit 1
    fi
    
    log_message "INFO: The current booted environment is as follows"
    log_message ""
    print_partition_state "${unraid_partitions[0]}" "${unraid_indices[0]}"
    
    debug_print "Boot UUID set to: $BOOT_UUID"
    debug_print "Boot mount set to: $BOOT_MOUNT"
    debug_print "Boot size set to: $BOOT_SIZE bytes"
    
    # Step 4: Scan for UNRAID_DR partition
    local clone_found=false
    for i in "${!current_drive_state[@]}"; do
        local row="${current_drive_state[$i]}"
        local label=$(get_column_value "$row" "LABEL")
        
        if [[ "$label" == "UNRAID_DR" ]]; then
            clone_found=true
            debug_print "Found UNRAID_DR partition"
            break
        fi
    done
    
    # Step 5 & 6: Call appropriate function based on whether clone exists
    if [ "$clone_found" = true ]; then
        clone_backup
    else
        find_and_prepare_clone
    fi
}

# Initialize logging
if ! setup_logging; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Failed to setup logging. Exiting." >&2
    exit 1
fi

log_message "INFO: Starting UNRAID boot partition check script"

# Run the main function
initial_test

log_message "INFO: UNRAID boot partition check completed successfully"