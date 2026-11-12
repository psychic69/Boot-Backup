#!/bin/bash

#===============================================
# INTERACTIVE SCRIPT CHECK
# This script is interactive and must be run from a TTY (SSH session).
# It cannot be run from the Unraid User Scripts plugin.
#===============================================
if [ ! -t 0 ]; then
    echo "FATAL: This script (dr_usb_create.sh) is interactive and must be run from an SSH terminal." >&2
    echo "FATAL: Please SSH into your Unraid server and run this script manually." >&2
    echo "FATAL: For scheduled backups, use dr_usb_backup.sh." >&2
    exit 1
fi

# Global variables
declare -a current_drive_state
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
# UNRAID SERVER CHECK
# The backup USB must be created on the Unraid server whose /boot it will back up.
# (Skipped with -lsblk: that test mode only reads a sample file and never changes a drive.)
#===============================================
if [ "$USE_TEST_FILE" != true ]; then
    if [ ! -f /etc/unraid-version ] && ! uname -a | grep -q "Unraid"; then
        echo "FATAL: This does not look like an Unraid server." >&2
        echo "FATAL: dr_usb_create.sh must be run on the Unraid server that holds the boot drive you want to protect." >&2
        exit 1
    fi
    if ! mountpoint -q /boot; then
        echo "FATAL: /boot is not mounted. dr_usb_create.sh must be run on the running Unraid server." >&2
        exit 1
    fi
fi

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
    local drive_size_bytes=$(lsblk -b -n -d -o SIZE "${device}")
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
    # Unmount anything mounted from the target device (e.g. auto-mounted by Unassigned Devices).
    # A mounted device cannot be wiped or formatted, so stop before changing anything if this fails.
    local mounts part_name part_mp
    mounts=$(lsblk -nr -o NAME,MOUNTPOINT "${device}" 2>/dev/null)
    while read -r part_name part_mp; do
        [ -n "${part_mp}" ] || continue
        if [ "${part_mp}" = "/boot" ]; then
            log_message "ERROR: /dev/${part_name} is mounted at /boot. Refusing to wipe the running Unraid boot drive."
            return 1
        fi
        log_message "INFO: Unmounting /dev/${part_name} (mounted at ${part_mp}) before wiping..."
        if ! run_logged "umount" umount "/dev/${part_name}"; then
            log_message "ERROR: Could not unmount /dev/${part_name}. Nothing was changed. Unmount it manually and re-run."
            return 1
        fi
    done <<< "${mounts}"
    log_message "INFO: Wiping existing signatures and creating new partition on ${device}..."
    debug_print "Running wipefs -a ${device}"
    if ! run_logged "wipefs" wipefs -a "${device}"; then
        log_message "ERROR: wipefs failed on ${device}"
        return 1
    fi
    debug_print "Running sfdisk ${device} with definition: ${sfdisk_partition_def}"
    if ! run_logged "sfdisk" sfdisk "${device}" <<< "${sfdisk_partition_def}"; then
        log_message "ERROR: Failed to partition ${device} with sfdisk"
        return 1
    fi
    log_message "INFO: Partition table created successfully"
    debug_print "Running partprobe ${device}"
    if ! run_logged "partprobe" partprobe "${device}"; then
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
    if ! run_logged "mkfs.vfat" mkfs.vfat -F 32 -n "UNRAID_DR" "${partition}"; then
        log_message "ERROR: Failed to format ${partition} as VFAT"
        return 1
    fi
    log_message "INFO: Process complete. ${device} is partitioned, formatted, and labeled 'UNRAID_DR'."
    return 0
}

# --- Shorten the output of convert_bytes_to_human to just the size (e.g. "14.50G") ---
size_short() {
    local human
    human=$(convert_bytes_to_human "$1")
    echo "${human%% (*}"
}

# --- Scan every USB disk and sort it into "selectable" or "not available" ---
# Fills these parallel arrays (global, reset on each call):
#   sel_dev / sel_model / sel_size / sel_star / sel_detail   - drives the user may choose
#   bad_dev / bad_model / bad_size / bad_reason              - drives shown for information only
# sel_star is "true" when the drive already contains partitions, a label or a filesystem signature.
# sel_detail holds one line per existing partition (newline separated).
scan_usb_disks() {
    local min_required_size="$1"
    sel_dev=(); sel_model=(); sel_size=(); sel_star=(); sel_detail=()
    bad_dev=(); bad_model=(); bad_size=(); bad_reason=()

    local i j
    for i in "${!current_drive_state[@]}"; do
        local row="${current_drive_state[$i]}"
        local disk size model
        [[ "$(get_column_value "$row" "TRAN")" == "usb" ]] || continue
        disk=$(get_column_value "$row" "NAME")
        size=$(get_column_value "$row" "SIZE")
        model=$(lsblk -n -d -o MODEL "/dev/$disk" 2>/dev/null | xargs)
        [[ -n "$model" ]] || model="Unknown"
        debug_print "Scanning USB disk: $disk (size=$size model='$model')"

        local has_data=false is_boot=false is_ventoy=false mounted_at="" detail=""
        for j in "${!current_drive_state[@]}"; do
            local r="${current_drive_state[$j]}"
            local n fs label mp psize
            n=$(get_column_value "$r" "NAME")
            local is_child=false
            if [[ "$n" == "$disk" ]]; then
                is_child=false
            elif [[ "$n" =~ ^${disk}p?[0-9]+$ ]]; then
                is_child=true
            else
                continue
            fi
            fs=$(get_column_value "$r" "FSTYPE")
            label=$(get_column_value "$r" "LABEL")
            mp=$(get_column_value "$r" "MOUNTPOINT")
            psize=$(get_column_value "$r" "SIZE")

            if [[ "$label" == "UNRAID" ]] || [[ "$mp" == "/boot" ]]; then is_boot=true; fi
            if [[ "$label" == "Ventoy" ]] || [[ "$label" == "VTOYEFI" ]]; then is_ventoy=true; fi
            if [[ -n "$mp" ]] && [[ "$mp" != "/boot" ]]; then mounted_at="$mp"; fi

            local label_disp="(none)"
            [[ -n "$label" ]] && label_disp="\"$label\""
            if [[ "$is_child" == true ]]; then
                has_data=true
                detail+=$(printf '        %-9s %-7s label: %-16s %s' "$n" "${fs:-none}" "$label_disp" "$(size_short "$psize")")$'\n'
            elif [[ -n "$fs" ]] || [[ -n "$label" ]]; then
                has_data=true
                detail+=$(printf '        (no partition table) filesystem: %s  label: %s' "${fs:-none}" "$label_disp")$'\n'
            fi
        done

        local reasons=()
        [[ "$is_boot" == true ]] && reasons+=("Unraid boot drive (label UNRAID / mounted at /boot)")
        [[ "$is_ventoy" == true ]] && reasons+=("Ventoy recovery USB (labels Ventoy / VTOYEFI)")
        [[ -n "$mounted_at" ]] && reasons+=("in use: a partition is mounted at $mounted_at")
        if ! [[ "$size" =~ ^[0-9]+$ ]] || (( size < min_required_size )); then
            reasons+=("too small: $(size_short "$size"), minimum is $(size_short "$min_required_size") (95% of the Unraid boot drive size)")
        fi

        if [ ${#reasons[@]} -gt 0 ]; then
            local joined="" r2
            for r2 in "${reasons[@]}"; do joined+="${joined:+; }$r2"; done
            bad_dev+=("$disk"); bad_model+=("$model"); bad_size+=("$size"); bad_reason+=("$joined")
        else
            sel_dev+=("$disk"); sel_model+=("$model"); sel_size+=("$size")
            sel_star+=("$has_data"); sel_detail+=("$detail")
        fi
    done
}

# --- Print the drive menu (selectable drives, then drives that are not available) ---
print_usb_menu() {
    local boot_size_human="$1"
    local any_star=false
    local i line
    log_message ""
    log_message "=========================================="
    log_message "Select the drive to become your backup USB (must be at least 95% of the boot drive size: $boot_size_human)"
    log_message "=========================================="
    log_message ""
    for i in "${!sel_dev[@]}"; do
        local mark=""
        if [[ "${sel_star[$i]}" == true ]]; then mark="  *"; any_star=true; fi
        log_message "  ${sel_dev[$i]}   ${sel_model[$i]}   $(size_short "${sel_size[$i]}")$mark"
        if [[ "${sel_star[$i]}" == true ]]; then
            while IFS= read -r line; do
                [[ -n "$line" ]] && log_message "$line"
            done <<< "${sel_detail[$i]}"
        fi
    done
    if [ "$any_star" = true ]; then
        log_message ""
        log_message "  * = this drive already contains data. Formatting it will ERASE everything listed under it."
    fi
    if [ ${#bad_dev[@]} -gt 0 ]; then
        log_message ""
        log_message "Not available (cannot be selected):"
        for i in "${!bad_dev[@]}"; do
            log_message "  ${bad_dev[$i]}   ${bad_model[$i]}   $(size_short "${bad_size[$i]}")"
            log_message "        ${bad_reason[$i]}"
        done
    fi
    log_message ""
}

# --- Last-moment safety check on the chosen disk (fresh data, not the earlier snapshot) ---
recheck_selected_device() {
    local device="$1" line name label mp
    while IFS= read -r line; do
        name=$(get_column_value "$line" "NAME")
        label=$(get_column_value "$line" "LABEL")
        mp=$(get_column_value "$line" "MOUNTPOINT")
        if [[ "$label" == "UNRAID" ]] || [[ "$mp" == "/boot" ]]; then
            log_message "ERROR: $device contains the Unraid boot partition ($name). Refusing to format it."
            return 1
        fi
        if [[ "$label" == "Ventoy" ]] || [[ "$label" == "VTOYEFI" ]]; then
            log_message "ERROR: $device looks like your Ventoy recovery USB ($name). Refusing to format it."
            return 1
        fi
    done < <(lsblk -P -o NAME,LABEL,MOUNTPOINT "$device" 2>/dev/null)
    return 0
}

# --- Function to find and prepare clone drive (INTERACTIVE) ---
find_and_prepare_clone() {
    log_message "INFO: No UNRAID_DR partition found. Searching for suitable USB drives..."
    local min_required_size
    min_required_size=$(awk "BEGIN {printf \"%.0f\", $BOOT_SIZE * 0.95}")
    local boot_size_human
    boot_size_human=$(size_short "$BOOT_SIZE")
    debug_print "Boot size: $BOOT_SIZE bytes"
    debug_print "Minimum required size (95%): $min_required_size bytes"

    scan_usb_disks "$min_required_size"
    print_usb_menu "$boot_size_human"

    if [ ${#sel_dev[@]} -eq 0 ]; then
        log_message "ERROR: No USB drive is available to use as the backup drive."
        log_message "ERROR: Connect a USB drive that is large enough and not in use (see the reasons above), then run this script again."
        exit 1
    fi
    log_message "INFO: Found ${#sel_dev[@]} selectable USB drive(s)."

    if [ "$DEBUG" = true ]; then
        local d
        for d in "${sel_dev[@]}"; do
            run_logged "fdisk" fdisk -l "/dev/$d"
        done
    fi

    local selected_device=""
    local attempt=0
    local max_attempts=2
    local device selected_ok
    while [ $attempt -lt $max_attempts ]; do
        read -rp "Enter device name (e.g., sdh): " selected_device
        debug_print "User entered device: '$selected_device'"
        selected_ok=false
        for device in "${sel_dev[@]}"; do
            if [[ "$device" == "$selected_device" ]]; then
                selected_ok=true
                break
            fi
        done
        if [ "$selected_ok" = true ]; then
            log_message "INFO: Device $selected_device selected."
            break
        fi
        # Explain why an unavailable drive was refused
        local idx
        for idx in "${!bad_dev[@]}"; do
            if [[ "${bad_dev[$idx]}" == "$selected_device" ]]; then
                log_message "ERROR: '$selected_device' cannot be selected: ${bad_reason[$idx]}"
            fi
        done
        ((attempt++))
        if [ $attempt -lt $max_attempts ]; then
            log_message "ERROR: Device '$selected_device' is not in the selectable list. Please try again."
        else
            log_message "ERROR: Device '$selected_device' is not in the selectable list. Maximum attempts reached."
            log_message "ERROR: Exiting script."
            exit 1
        fi
    done
    log_message ""
    log_message "=========================================="
    log_message "WARNING: Be aware the device /dev/$selected_device will be formatted and wiped."
    log_message "WARNING: All data on this device will be permanently lost!"
    log_message "=========================================="
    local idx2
    for idx2 in "${!sel_dev[@]}"; do
        if [[ "${sel_dev[$idx2]}" == "$selected_device" ]]; then
            if [[ "${sel_star[$idx2]}" == true ]]; then
                log_message "This drive currently contains (and ALL of it will be erased):"
                local dl
                while IFS= read -r dl; do
                    [[ -n "$dl" ]] && log_message "$dl"
                done <<< "${sel_detail[$idx2]}"
            else
                log_message "This drive appears to be blank."
            fi
        fi
    done
    log_message "Are you sure you want to do this? If so, type FORMAT in all capitals:"
    log_message ""
    local confirmation=""
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        read -rp "Type FORMAT to confirm: " confirmation
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
    if [ "$DEBUG" = true ] || [ "$USE_TEST_FILE" = true ]; then
        log_message "INFO: DEBUG/TEST MODE - /dev/$selected_device was NOT changed."
        log_message "INFO: DEBUG/TEST MODE - Would wipe, partition (type b), format as FAT32 'UNRAID_DR', then run the initial clone backup."
        return 0
    fi
    if ! recheck_selected_device "/dev/$selected_device"; then
        exit 1
    fi
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
if ! setup_logging "usb-create"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: Failed to setup logging. Exiting." >&2
    exit 1
fi
# Keep only the newest create log: remove earlier ones whose run completed successfully.
remove_old_successful_logs "${LOG_DIR}/logs" "usb-create-*.log" "${LOG_FILE}" "CREATE** script completed."

log_message "INFO: Starting UNRAID DR USB **CREATE** script (Interactive)"
if [ "$DEBUG" = true ] || [ "$USE_TEST_FILE" = true ]; then
    log_message "INFO: DEBUG/TEST MODE: extra detail is logged and NOTHING will be formatted or changed. Run without -debug/-lsblk to create the USB."
fi
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

# Run the main function
main_create
create_rc=$?

if [ $create_rc -ne 0 ]; then
    log_message "ERROR: UNRAID DR USB **CREATE** script finished WITH ERRORS (exit $create_rc)."
else
    log_message "INFO: UNRAID DR USB **CREATE** script completed."
fi
exit $create_rc