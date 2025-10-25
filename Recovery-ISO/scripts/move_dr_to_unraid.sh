#!/bin/bash

# A script to restore the Unraid bootloader from a backup USB.
# Run this from the SystemRescue emergency environment.

# --- Configuration ---
BACKUP_LABEL="UNRAID_DR"
FINAL_LABEL="UNRAID"
MOUNT_POINT="/mnt/unraid_temp"

# NOTE: We do NOT use 'set -e' because some commands are expected to return
# non-zero when searching for devices that may not exist

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

# First, find all partitions with the BACKUP_LABEL
MATCHING_PARTITIONS=$(lsblk -p -n -l -o NAME,LABEL | grep -w "$BACKUP_LABEL" | awk '{print $1}')

# Count how many partitions were found
PARTITION_COUNT=0
if [ -n "$MATCHING_PARTITIONS" ]; then
    PARTITION_COUNT=$(echo "$MATCHING_PARTITIONS" | wc -l)
fi

if [ "$PARTITION_COUNT" -eq 0 ]; then
    echo "🛑 ERROR: No drive with the label '$BACKUP_LABEL' was found."
    echo "   Please plug in the correct backup USB drive and try again."
    exit 1
fi

# Now check each partition to see if it's on a USB drive
declare -a USB_BACKUP_PARTITIONS
declare -a USB_BACKUP_DEVICES
declare -a USB_BACKUP_INFO

while IFS= read -r PART_PATH; do
    [ -z "$PART_PATH" ] && continue
    
    # Get parent device path (e.g., /dev/sda from /dev/sda1)
    PARENT_DEV=$(lsblk -p -n -o PKNAME "$PART_PATH" | head -n 1)
    
    # Get transport type from parent device
    eval $(lsblk -p -n -P -o TRAN "$PARENT_DEV" | head -n 1)
    TRANSPORT="$TRAN"
    
    # Check if it's a USB device
    if [ "$TRANSPORT" = "usb" ]; then
        USB_BACKUP_PARTITIONS+=("$PART_PATH")
        USB_BACKUP_DEVICES+=("$PARENT_DEV")
        USB_BACKUP_INFO+=("$PART_PATH (device: $PARENT_DEV)")
    fi
done <<< "$MATCHING_PARTITIONS"

# Check the count of USB drives found
USB_DRIVE_COUNT=${#USB_BACKUP_PARTITIONS[@]}

if [ "$USB_DRIVE_COUNT" -eq 0 ]; then
    echo "🛑 ERROR: No *USB* drive with the label '$BACKUP_LABEL' was found."
    echo "   Found partition(s) with that label, but they are not on USB drives."
    echo
    echo "   Non-USB drives with label '$BACKUP_LABEL':"
    echo "$MATCHING_PARTITIONS"
    echo
    echo "   Please plug in the correct backup USB drive and try again."
    exit 1

elif [ "$USB_DRIVE_COUNT" -gt 1 ]; then
    echo "🛑 ERROR: Found *multiple* USB drives with the label '$BACKUP_LABEL'."
    echo "   This is ambiguous. Please remove the extra drive(s) and leave only the one you wish to use."
    echo
    echo "   Found USB drives:"
    for info in "${USB_BACKUP_INFO[@]}"; do
        echo "   - $info"
    done
    exit 1
fi

# If we are here, count is exactly 1. We can now safely use the device paths.
BACKUP_PART_PATH="${USB_BACKUP_PARTITIONS[0]}"  # e.g., /dev/sdc1
BACKUP_DRIVE_PATH="${USB_BACKUP_DEVICES[0]}"    # e.g., /dev/sdc

echo "✅ Found one and only one matching USB drive."
echo "   Partition: $BACKUP_PART_PATH"
echo "   Device:    $BACKUP_DRIVE_PATH"

# --- 3. Unmount, Relabel, and Run Script ---

# Unmount just in case it was auto-mounted
umount "$BACKUP_PART_PATH" &>/dev/null || true

echo "Changing label from '$BACKUP_LABEL' to '$FINAL_LABEL'..."
# Use fatlabel from dosfstools to change the FAT32 label (modern replacement for mlabel)
if ! fatlabel "$BACKUP_PART_PATH" "$FINAL_LABEL"; then
    echo "🛑 ERROR: Failed to change label. The partition may not be FAT32."
    exit 1
fi

echo "Making the drive bootable..."
mkdir -p "$MOUNT_POINT"

if ! mount "$BACKUP_PART_PATH" "$MOUNT_POINT"; then
    echo "🛑 ERROR: Failed to mount $BACKUP_PART_PATH"
    rmdir "$MOUNT_POINT" 2>/dev/null
    exit 1
fi

SCRIPT_PATH="$MOUNT_POINT/make_bootable_linux.sh"
if [ -f "$SCRIPT_PATH" ]; then
    # Change into the directory before running the script.
    # This is safer as the script may rely on relative paths.
    echo "Running make_bootable_linux.sh..."
    if ! (cd "$MOUNT_POINT" && bash ./make_bootable_linux.sh); then
        echo "🛑 ERROR: make_bootable_linux.sh failed"
        umount "$MOUNT_POINT"
        rmdir "$MOUNT_POINT"
        exit 1
    fi
    echo "Successfully ran the make_bootable script."
else
    echo "🛑 ERROR: Could not find 'make_bootable_linux.sh' on the drive."
    echo "   Expected location: $SCRIPT_PATH"
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
