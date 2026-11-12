#!/bin/bash

# Global variables
declare -a current_drive_state
declare -a clone_array
DEBUG=false
USE_TEST_FILE=false
LOG_FILE=""
BOOT_SIZE=""
CLONE_DEVICE=""
BOOT_DIR="/boot"      # the Unraid flash drive; only the tests change this

# Handle argument parsing for both User Scripts (passes path or "" as $1) 
# and standalone execution.

# Check if $1 exists AND is NOT a flag (i.e., doesn't start with "-").
# This will catch a path like "/boot/..." or an empty string ""
# but will correctly skip a flag like "-debug".
if [[ $# -gt 0 ]] && [[ "$1" != -* ]]; then
    # It's the path or an empty string from User Scripts.
    # We don't need the value, so we just shift it off the stack.
    shift
fi

# Now, parse the *remaining* arguments (e.g., -debug, -lsblk, or nothing)
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
# SHARED MODULES (lib/) AND SETTINGS
# Settings (log location, retention, mount point) now live in dr_usb.ini beside this script;
# see dr_usb.ini.example. Defaults are built in, so the file is optional.
#===============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
for _lib in logging drives integrity clone config; do
    if [ ! -f "${LIB_DIR}/${_lib}.sh" ]; then
        echo "FATAL: Missing module ${LIB_DIR}/${_lib}.sh" >&2
        echo "FATAL: Install the full release archive into /boot/config/plugins/dr_usb/ and run the script from there." >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "${LIB_DIR}/${_lib}.sh"
done
unset _lib




# --- Main function (Backup) ---
main_backup() {
    # Load the drive state
    if ! load_drive_state; then
        log_message "FATAL: Failed to load drive state"
        exit 1
    fi
    
    # Find the main UNRAID boot partition for logging
    local unraid_found=false
    for i in "${!current_drive_state[@]}"; do
        local row="${current_drive_state[$i]}"
        local label=$(get_column_value "$row" "LABEL")
        local name=$(get_column_value "$row" "NAME")
        local mountpoint=$(get_column_value "$row" "MOUNTPOINT")
        
        if [[ "$label" == "UNRAID" ]] && [[ "$name" =~ 1$ ]] && [[ "$mountpoint" == "/boot" ]]; then
            log_message "INFO: Verified UNRAID boot partition is mounted at /boot"
            print_partition_state "$row" "$i"
            unraid_found=true
            break
        fi
    done
    
    if [ "$unraid_found" = false ]; then
        log_message "FATAL: Could not find the primary 'UNRAID' partition mounted at /boot. Aborting."
        exit 1
    fi
    
    # Scan for UNRAID_DR partition
    local -a unraid_dr_partitions
    local -a unraid_dr_devices
    local -a unraid_dr_models
    local -a unraid_dr_sizes
    local -a unraid_dr_indices

    for i in "${!current_drive_state[@]}"; do
        local row="${current_drive_state[$i]}"
        local label=$(get_column_value "$row" "LABEL")
        local name=$(get_column_value "$row" "NAME")
        
        if [[ "$label" == "UNRAID_DR" ]]; then
            debug_print "Found UNRAID_DR partition: $name"
            unraid_dr_partitions+=("$row")
            unraid_dr_indices+=("$i")
            
            # Extract parent device name from partition name
            local parent_device=$(echo "$name" | sed 's/[0-9]*$//' | sed 's/p$//')
            
            # Get parent device size and model
            local parent_size=""
            local parent_model="Unknown"
            
            for j in "${!current_drive_state[@]}"; do
                local check_row="${current_drive_state[$j]}"
                local check_name=$(get_column_value "$check_row" "NAME")
                
                if [[ "$check_name" == "$parent_device" ]]; then
                    parent_size=$(get_column_value "$check_row" "SIZE")
                    parent_model=$(lsblk -n -d -o MODEL "/dev/$parent_device" 2>/dev/null | xargs)
                    if [[ -z "$parent_model" ]]; then
                        parent_model="Unknown"
                    fi
                    break
                fi
            done
            
            unraid_dr_devices+=("/dev/$parent_device")
            unraid_dr_models+=("$parent_model")
            unraid_dr_sizes+=("$parent_size")
        fi
    done

    # --- Main Logic Fork ---
    if [ ${#unraid_dr_partitions[@]} -eq 0 ]; then
        log_message "ERROR: No 'UNRAID_DR' backup partition was found."
        log_message "ERROR: Please run the 'dr_usb_create.sh' script from an SSH terminal to set one up."
        exit 1
    
    elif [ ${#unraid_dr_partitions[@]} -gt 1 ]; then
        log_message "ERROR: Multiple partitions with the label 'UNRAID_DR' found. You must have only one."
        log_message "ERROR: Please remove the 'UNRAID_DR' label from all but one of the following devices:"
        log_message ""
        
        for idx in "${!unraid_dr_devices[@]}"; do
            local size_human=$(convert_bytes_to_human "${unraid_dr_sizes[$idx]}")
            log_message "  - Device: ${unraid_dr_devices[$idx]}"
            log_message "    Model: ${unraid_dr_models[$idx]}"
            log_message "    Size: $size_human"
            log_message ""
        done
        
        log_message "ERROR: Exiting script. Please resolve the duplicate UNRAID_DR labels."
        exit 1
    
    else
        # Exactly one partition found, proceed with backup.
        local clone_row="${unraid_dr_partitions[0]}"
        local clone_device="${unraid_dr_devices[0]}"
        local clone_row_index="${unraid_dr_indices[0]}"

        CLONE_DEVICE="$clone_device"
        log_message "INFO: Found target 'UNRAID_DR' backup drive: $CLONE_DEVICE"
        debug_print "Global CLONE_DEVICE set to: $CLONE_DEVICE"
        
        log_message "INFO: The current UNRAID_DR clone drive is as follows"
        log_message ""
        print_partition_state "$clone_row" "$clone_row_index"
        
        log_message "INFO: Proceeding with non-interactive backup..."
        clone_backup "$CLONE_DEVICE"
    fi
}
####################MAIN CODE EXECUTION

# Load settings (defaults + optional dr_usb.ini), then validate. This must be run before logging is set up.
if ! load_config; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Could not load settings. Exiting." >&2
    exit 1
fi
if ! validate_parameters; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Parameter validation failed. Exiting." >&2
    exit 1
fi

# Initialize logging using the validated parameters
if ! setup_logging "boot-check"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Failed to setup logging. Exiting." >&2
    exit 1
fi
file_rotation "${LOG_DIR}/logs" "boot-check-*.log" "$((SNAPSHOTS * 2))" "${RETENTION_DAYS}"

log_message "INFO: Starting UNRAID DR USB **BACKUP** script (Non-Interactive)"
log_message "INFO: Configuration parameters:"
if [ "$DR_USB_INI_LOADED" = true ]; then
    log_message "INFO:   Settings file: $DR_USB_INI"
else
    log_message "INFO:   Settings file: (none found, using built-in defaults)"
fi
log_message "INFO:   LOG_DIR=$LOG_DIR"
log_message "INFO:   SNAPSHOTS=$SNAPSHOTS"
log_message "INFO:   RETENTION_DAYS=$RETENTION_DAYS"
log_message "INFO:   CLONE_MP=$CLONE_MP"

log_message "INFO: Cloning /boot to the UNRAID_DR USB"
main_backup
backup_rc=$?
if [ $backup_rc -ne 0 ]; then
    notify_failure "Boot backup to the UNRAID_DR USB failed. See log: $LOG_FILE"
fi

if [ $backup_rc -ne 0 ]; then
    log_message "ERROR: UNRAID DR USB **BACKUP** script finished WITH ERRORS (exit $backup_rc)."
else
    log_message "INFO: UNRAID DR USB **BACKUP** script completed."
fi
exit $backup_rc