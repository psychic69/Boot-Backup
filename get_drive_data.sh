#!/bin/bash

# Define the output columns explicitly, including the transport (TRAN) for filtering.
# We include NAME, MODEL, SIZE, and TRAN
OUTPUT_COLUMNS="NAME,MODEL,SIZE,TRAN"

# Use -r (raw) and -o (output columns) for stable, machine-parsable output, separated by spaces.
# The --nodeps flag ensures only main devices are listed.

lsblk -o "$OUTPUT_COLUMNS" -r --nodeps | tail -n +2 | \
awk '$4 == "usb" {print $0}' | \
while read -r DEV_NAME MODEL SIZE TRAN; do

    # Note: The raw output format (-r) uses space separation and suppresses the visual tree.
    
    # Clean up the model string by removing quotes, which can appear in raw output
    CLEAN_MODEL=$(echo "$MODEL" | tr -d '"')

    # Find symbolic links in /dev/disk/by-id/ that point to the device
    # This path is essential for reliable identification.
    # The find command will search for symlinks pointing to the device node (e.g., /dev/sdb)
    BY_ID_PATH=$(find /dev/disk/by-id -lname "*/$DEV_NAME" -printf " %p" 2>/dev/null)
    
    # Output the result using a clear, consistent pipe (|) separated format.
    echo "${DEV_NAME}|${CLEAN_MODEL}|${SIZE}|${BY_ID_PATH}"
done