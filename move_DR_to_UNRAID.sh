#!/bin/bash

# A script to restore the Unraid bootloader from a backup USB.
# Run this from the SystemRescue emergency environment.

# --- Configuration ---
BACKUP_LABEL="UNRAID_DR"
FINAL_LABEL="UNRAID"
MOUNT_POINT="/mnt/unraid_temp"

# Exit immediately if a command fails
set -e

# --- 1. PRE-CHECK: Ensure no "UNRAID" drive already exists ---
echo "Checking for existing '$FINAL_LABEL' drive..."

# Find a partition name (e.g., sda1) that *exactly* matches the FINAL_LABEL
# The '-w' flag for grep ensures it matches the whole word "UNRAID" and not "UNRAID_DR"
CONFLICT_PART_NAME=$(lsblk -o NAME,LABEL | grep -w "$FINAL_LABEL" | awk '{print $1}')

if [ -n "$CONFLICT_PART_NAME" ]; then
    # Found a conflict. Gather detailed info.
    CONFLICT_DEV_PATH="/dev/$CONFLICT_PART_NAME"
    
    # Get all info in one line using lsblk's list format.
    # -p: full path, -n: no tree, -l: list, -b: size in bytes
    INFO_LINE=$(lsblk -p -n -l -b -o NAME,MOUNTPOINT,UUID,FSTYPE,LABEL,SIZE,TRAN "$CONFLICT_DEV_PATH")

    # Parse the info
    DRIVE_LOC=$(echo "$INFO_LINE" | awk '{print $1}')
    MOUNTPOINT=$(echo "$INFO_LINE" | awk '{print $2}')
    UUID=$(echo "$INFO_LINE" | awk '{print $3}')
    FSTYPE=$(echo "$INFO_LINE" | awk '{print $4}')
    LABEL=$(echo "$INFO_LINE" | awk '{print $5}')
    SIZE_BYTES=$(echo "$INFO_LINE" | awk '{print $6}')
    TRANSPORT=$(echo "$INFO_LINE" | awk '{print $7}')
    
    # Make size human-readable (e.g., 7.54G)
    SIZE_HUMAN=$(numfmt --to=iec-i --suffix=B --format="%.2f" "$SIZE_BYTES")

    # Print the detailed error message and exit
    echo "🛑 ERROR: A drive with the label '$FINAL_LABEL' already exists."
    echo "   This script is for emergencies where the '$FINAL_LABEL' drive is *missing* or *dead*."
    echo "   Please remove the conflicting drive and try again."
    echo
    echo "   Detailed information on conflicting drive:"
    echo "   -------------------------------------------"
    echo "   Drive location:   $DRIVE_LOC"
    echo "   Current Mountpoint: $MOUNTPOINT"
    echo "   UUID:             $UUID"
    echo "   File type:        $FSTYPE"
    echo "   Current Label:    $LABEL"
    echo "   Drive Size:       $SIZE_HUMAN ($SIZE_BYTES bytes)"
    echo "   Transport Type:   $TRANSPORT"
    
    exit 1
fi

echo "No conflicting '$FINAL_LABEL' drive found. Proceeding..."
echo "---"

# --- 2. Find ONE and ONLY ONE USB Backup Drive ---
echo "Searching for a *single* USB drive with label '$BACKUP_LABEL'..."

# Get a list of partitions that match the LABEL and are transport type 'usb'
# -p: full path, -n: no tree, -l: list format
# We grep for word-boundary 'usb' to be safe
MATCHING_USB_DRIVES_INFO=$(lsblk -p -n -l -o NAME,LABEL,TRAN | grep -w "$BACKUP_LABEL" | grep '\busb\b')

# Count how many were found
USB_DRIVE_COUNT=0
if [ -n "$MATCHING_USB_DRIVES_INFO" ]; then
    USB_DRIVE_COUNT=$(echo "$MATCHING_USB_DRIVES_INFO" | wc -l)
fi

# Check the count
if [ "$USB_DRIVE_COUNT" -eq 0 ]; then
    echo "🛑 ERROR: No *USB* drive with the label '$BACKUP_LABEL' was found."
    echo "   Please plug in the correct backup USB drive and try again."
    
    # Check if we found any non-USB drives with that label, to be helpful
    NON_USB_DRIVES=$(lsblk -p -n -l -o NAME,LABEL,TRAN | grep -w "$BACKUP_LABEL" | grep -v '\busb\b')
    if [ -n "$NON_USB_DRIVES" ]; then
        echo
        echo "   Note: Found non-USB drive(s) with that label:"
        echo "$NON_USB_DRIVES"
    fi
    exit 1

elif [ "$USB_DRIVE_COUNT" -gt 1 ]; then
    echo "🛑 ERROR: Found *multiple* USB drives with the label '$BACKUP_LABEL'."
    echo "   This is ambiguous. Please remove the extra drive(s) and leave only the one you wish to use."
    echo
    echo "   Found drives:"
    echo "$MATCHING_USB_DRIVES_INFO"
    exit 1
fi

# If we are here, count is exactly 1. We can now safely get the device paths.
BACKUP_PART_PATH=$(echo "$MATCHING_USB_DRIVES_INFO" | awk '{print $1}') # e.g., /dev/sdc1
BACKUP_DRIVE_PATH=$(lsblk -p -n -o PKNAME "$BACKUP_PART_PATH")         # e.g., /dev/sdc

echo "✅ Found one and only one matching USB drive."
echo "   Partition: $BACKUP_PART_PATH"
echo "   Device:    $BACKUP_DRIVE_PATH"

# --- 3. Unmount, Relabel, and Run Script ---

# Unmount just in case it was auto-mounted
umount "$BACKUP_PART_PATH" &>/dev/null || true

echo "Changing label from '$BACKUP_LABEL' to '$FINAL_LABEL'..."
# Use mlabel from dosfstools to change the FAT32 label
mlabel -i "$BACKUP_PART_PATH" ::"$FINAL_LABEL"

echo "Making the drive bootable..."
mkdir -p "$MOUNT_POINT"
mount "$BACKUP_PART_PATH" "$MOUNT_POINT"

SCRIPT_PATH="$MOUNT_POINT/make_bootable_linux.sh"
if [ -f "$SCRIPT_PATH" ]; then
    # Change into the directory before running the script.
    # This is safer as the script may rely on relative paths.
    (cd "$MOUNT_POINT" && bash ./make_bootable_linux.sh)
    echo "Successfully ran the make_bootable script."
else
    echo "Error: Could not find 'make_bootable_linux.sh' on the drive."
    umount "$MOUNT_POINT"
    rmdir "$MOUNT_POINT"
    exit 1
fi

# --- 4. Cleanup ---
umount "$MOUNT_POINT"
rmdir "$MOUNT_POINT"
echo "---"
echo "✅ All done! The USB drive at '$BACKUP_DRIVE_PATH' should now be bootable as your main Unraid drive."
echo "You can now shut down and remove the emergency USB."