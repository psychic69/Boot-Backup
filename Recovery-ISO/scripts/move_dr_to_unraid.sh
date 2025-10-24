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

CONFLICT_PART_NAME=$(lsblk -n -l -o NAME,LABEL | grep -w "$FINAL_LABEL" | awk '{print $1}')

if [ -n "$CONFLICT_PART_NAME" ]; then
    # Found a conflict. Gather detailed info efficiently.
    CONFLICT_DEV_PATH="/dev/$CONFLICT_PART_NAME"
    
    # --- Get the parent device path (e.g., /dev/sda) ---
    PARENT_DEV_PATH=$(lsblk -p -n -o PKNAME "$CONFLICT_DEV_PATH" | head -n 1)

    # ---
    # EFFICIENT REFACTOR: Call lsblk once for partition data and once for transport data.
    # Use -P for KEY="VALUE" pairs and 'eval' to create local variables.
    # ---
    
    # 1. Get Partition Info. Variables like $NAME, $UUID, $SIZE, etc.,
    #    will be created by 'eval'.
    eval $(lsblk -p -n -P -b -o NAME,MOUNTPOINT,UUID,FSTYPE,LABEL,SIZE "$CONFLICT_DEV_PATH" | head -n 1)
    
    # 2. Get Transport Info from the Parent Device. This creates the $TRAN variable.
    eval $(lsblk -p -n -P -o TRAN "$PARENT_DEV_PATH" | head -n 1)

    # --- Assign to our script variables for clarity ---
    # (e.g., $NAME from eval is assigned to $DRIVE_LOC)
    DRIVE_LOC="$NAME"
    DR_MOUNTPOINT="$MOUNTPOINT"
    DR_UUID="$UUID"
    DR_FSTYPE="$FSTYPE"
    DR_LABEL="$LABEL"
    DR_SIZE_BYTES="$SIZE" # $SIZE is from eval, in bytes due to -b flag
    DR_TRANSPORT="$TRAN"  # $TRAN is from the second eval

    # Handle blank mountpoint
    if [ -z "$DR_MOUNTPOINT" ]; then
        DR_MOUNTPOINT="[none]"
    fi
    
    # Make size human-readable
    SIZE_HUMAN=$(numfmt --to=iec-i --suffix=B --format="%.2f" "$DR_SIZE_BYTES")

    # Print the detailed error message
    echo "🛑 ERROR: A drive with the label '$FINAL_LABEL' already exists."
    echo "   This script is for emergencies where the '$FINAL_LABEL' drive is *missing* or *dead*."
    echo "   Please remove the conflicting drive and try again."
    echo
    echo "   Detailed information on conflicting drive:"
    echo "   -------------------------------------------"
    echo "   Drive location:   $DRIVE_LOC"
    echo "   Current Mountpoint: $DR_MOUNTPOINT"
    echo "   UUID:             $DR_UUID"
    echo "   File type:        $DR_FSTYPE"
    echo "   Current Label:    $DR_LABEL"
    echo "   Drive Size:       $SIZE_HUMAN ($DR_SIZE_BYTES bytes)"
    echo "   Transport Type:   $DR_TRANSPORT"
    
    exit 1
fi

echo "No conflicting '$FINAL_LABEL' drive found. Proceeding..."
echo "---"

# --- 2. Find ONE and ONLY ONE USB Backup Drive ---
echo "Searching for a *single* USB drive with label '$BACKUP_LABEL'..."

# Get a list of partitions that match the LABEL and are transport type 'usb'
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
# Use fatlabel from dosfstools to change the FAT32 label (modern replacement for mlabel)
fatlabel "$BACKUP_PART_PATH" "$FINAL_LABEL"

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