#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- CONFIGURATION ---
# The target device is passed as the first argument to the script.
DEVICE="$1"

# --- INPUT VALIDATION ---
if [ -z "${DEVICE}" ]; then
    echo "🛑 Error: No device specified."
    echo "Usage: $0 /dev/sdX"
    exit 1
fi

if [ ! -b "${DEVICE}" ]; then
    echo "🛑 Error: Device ${DEVICE} is not a valid block device."
    echo "Please use a command like 'lsblk' to verify the device name."
    exit 1
fi

# --- CHECK DRIVE SIZE & PREPARE PARTITION DEFINITION ---
# Get the total size of the drive in bytes.
DRIVE_SIZE_BYTES=$(lsblk -b -n -d -o SIZE ${DEVICE})

# Define our maximum size: 64 GiB in bytes (64 * 1024^3).
MAX_SIZE_BYTES=$((64 * 1024 * 1024 * 1024))

# Variable to hold the partition definition for sfdisk.
SFDISK_PARTITION_DEF=""

if [ "${DRIVE_SIZE_BYTES}" -gt "${MAX_SIZE_BYTES}" ]; then
    echo "Drive is larger than 64GB. Creating a 64GB partition."
    # Define a partition of 64GB with type 'b' (W95 FAT32).
    SFDISK_PARTITION_DEF="size=64G, type=b"
else
    echo "Drive is 64GB or smaller. Using the entire drive."
    # Define a single partition of type 'b' using all available space.
    SFDISK_PARTITION_DEF="type=b"
fi

# --- PARTITION THE DRIVE ---
echo "Wiping existing signatures and creating new partition on ${DEVICE}..."
# First, wipe any existing filesystem or partition table signatures.
sudo wipefs -a "${DEVICE}"

# Use sfdisk to create the MBR partition table and partition in one step.
sudo sfdisk "${DEVICE}" <<< "${SFDISK_PARTITION_DEF}"

# Use partprobe to make sure the kernel recognizes the new partition table.
sudo partprobe "${DEVICE}"

# Short pause to ensure the device node is created.
sleep 2

# --- FORMAT THE PARTITION ---
# The new partition will be the device name followed by the number '1'.
PARTITION="${DEVICE}1"

echo "Formatting ${PARTITION} as VFAT (FAT32)..."
# The -n flag sets the volume name (label) to UNRAID_DR.
sudo mkfs.vfat -F 32 -n "UNRAID_DR" ${PARTITION}

echo "✅ Process complete. ${DEVICE} is partitioned, formatted, and labeled 'UNRAID_DR'."