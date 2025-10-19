#!/bin/bash

# --- CONFIGURATION ---
# IMPORTANT: Set this to the device you want to format (e.g., /dev/sdb, /dev/sdc).
# Use 'lsblk' to find the correct device name.
# DOUBLE-CHECK THIS VARIABLE. INCORRECTLY SETTING IT WILL WIPE THE WRONG DRIVE.
DEVICE="$1"

# --- SCRIPT ---

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Check Drive Size and Set Partition End Point ---

# Get the total size of the drive in bytes.
DRIVE_SIZE_BYTES=$(lsblk -b -n -d -o SIZE ${DEVICE})

# Define our maximum size: 64 GiB in bytes (64 * 1024^3).
MAX_SIZE_BYTES=$((64 * 1024 * 1024 * 1024))

# Variable to hold the end point for the parted command.
PARTITION_END=""

if [ "${DRIVE_SIZE_BYTES}" -gt "${MAX_SIZE_BYTES}" ]; then
    echo "Drive is larger than 64GB. Creating a 64GB partition."
    # Set the end of the partition to 64GB.
    PARTITION_END="64GB"
else
    echo "Drive is 64GB or smaller. Using the entire drive."
    # Set the end of the partition to 100% of the disk.
    PARTITION_END="100%"
fi

# --- Partition the Drive ---
echo "Partitioning ${DEVICE}..."
# Use the PARTITION_END variable to set the size.
sudo parted -s -a optimal ${DEVICE} -- mklabel gpt mkpart primary fat32 0% ${PARTITION_END}

# Use partprobe to make sure the kernel recognizes the new partition table.
sudo partprobe ${DEVICE}

# Short pause to ensure the device node is created.
sleep 2

# --- Format the Partition ---
# The new partition will be the device name followed by the number '1'.
PARTITION="${DEVICE}1"

echo "Formatting ${PARTITION} as VFAT (FAT32)..."
# The -n flag sets the volume name (label) of the partition.
sudo mkfs.vfat -F 32 -n "UNRAID_DR" ${PARTITION}

echo "✅ Process complete. ${DEVICE} is partitioned, formatted, and labeled 'UNRAID_CLONE'."